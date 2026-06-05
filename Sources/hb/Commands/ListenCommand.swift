import ArgumentParser
import AsyncAlgorithms
import FileMonitor
import Subprocess
import Synchronization
import System

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

private let building = Atomic(false)

struct ListenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "listen",
        abstract: "Listen for changes to your application source code and re-build and run it."
    )

    @Flag(name: [.customShort("s"), .long], help: "Use swiftly to run swift processes")
    var useSwiftly: Bool = false

    @Argument(help: "The executable to build and run.")
    var product: String? = nil

    // The arguments to pass to the executable.
    @Argument(
        parsing: .captureForPassthrough,
        help: "The arguments to pass to the executable."
    )
    var arguments: [String] = []

    var swiftPM: SwiftPM { .init(useSwiftly: self.useSwiftly) }

    var globalID = 0

    mutating func run() async throws {
        let targetProduct = try await self.swiftPM.getExecutableProduct(desiredProduct: self.product)
        let build = self.swiftPM.getCommand(["build", "--product", targetProduct])
        let run = try await SubprocessCommand(.path(self.swiftPM.getBinaryPath(product: targetProduct)), arguments: .init(arguments))

        try await withThrowingTaskGroup(of: Void.self) { group in
            let currentDirectory = FileManager.default.currentDirectoryPath
            let sourceDirectory = URL(filePath: currentDirectory, directoryHint: .isDirectory)
                .appending(path: "Sources", directoryHint: .isDirectory)
            let fileMonitor = try FileMonitor(directory: sourceDirectory)
            try fileMonitor.start()
            defer {
                fileMonitor.stop()
            }

            // Request to cancel run stream
            let (stream, cont) = AsyncStream.makeStream(of: Int.self)
            // Run has been cancelled stream
            let (cancelledStream, cancelledCont) = AsyncStream.makeStream(of: Int.self)

            // Initial build and run
            addBuildAndRunTasks(
                build: build,
                run: run,
                group: &group,
                requestCancelSteam: stream,
                cancelledStreamCont: cancelledCont
            )
            enum StreamEvent {
                case monitor(FileChange)
                case cancelledRun(Int)
            }
            // combine file monitor stream with cancelled runs stream
            let combinedStream = merge(fileMonitor.stream.map { StreamEvent.monitor($0) }, cancelledStream.map { .cancelledRun($0) })
            for try await event in combinedStream {
                switch event {
                case .monitor(.changed(let file)):
                    // A file changed, yield a cancel request and start a new build.
                    print("File changed \(file)")
                    cont.yield(globalID)
                    addBuildAndRunTasks(
                        build: build,
                        run: run,
                        group: &group,
                        requestCancelSteam: stream,
                        cancelledStreamCont: cancelledCont
                    )
                case .cancelledRun(let id):
                    // Only re-build if the id of this cancelled run is the same as the global ID ie another build has not been
                    // triggered
                    guard id == globalID else { continue }
                    addBuildAndRunTasks(
                        build: build,
                        run: run,
                        group: &group,
                        requestCancelSteam: stream,
                        cancelledStreamCont: cancelledCont
                    )
                default:
                    break
                }
            }

            group.cancelAll()
        }
    }

    /// Build target and once that has finished run the target
    mutating func addBuildAndRunTasks(
        build: SubprocessCommand,
        run: SubprocessCommand,
        group: inout ThrowingTaskGroup<Void, any Error>,
        requestCancelSteam: AsyncStream<Int>,
        cancelledStreamCont: AsyncStream<Int>.Continuation
    ) {
        // If we are already building return
        guard building.compareExchange(expected: false, desired: true, ordering: .relaxed).original == false else {
            return
        }
        self.globalID += 1
        let cancellation = SubProcessCancellation(id: globalID, stream: requestCancelSteam, cancelledStreamCont: cancelledStreamCont)
        // Run build
        group.addTask {
            let result: ExecutionResult<Void, FileDescriptorOutput, FileDescriptorOutput>
            do {
                defer {
                    building.store(false, ordering: .relaxed)
                }
                result = try await Subprocess.run(
                    build.executable,
                    arguments: build.arguments,
                    input: .standardInput,
                    output: .currentStandardOutput,
                    error: .currentStandardError
                ) { execution in
                }
            } catch {
                return
            }
            switch result.terminationStatus {
            case .exited(let status):
                guard status == 0 else {
                    print("Build failed.")
                    return
                }
            default:
                return
            }
            _ = try await Subprocess.run(
                run.executable,
                arguments: run.arguments,
                input: .standardInput,
                output: .currentStandardOutput,
                error: .currentStandardError
            ) { execution in
                print("PID: \(execution.processIdentifier)")
                if let _ = try await cancellation.wait() {
                    try execution.send(signal: .terminate)
                }
            }
        }
    }

    struct SubProcessCancellation: Sendable {
        let stream: AsyncStream<Int>
        let cancelledStreamCont: AsyncStream<Int>.Continuation
        let id: Int

        init(id: Int, stream: AsyncStream<Int>, cancelledStreamCont: AsyncStream<Int>.Continuation) {
            self.id = id
            self.stream = stream
            self.cancelledStreamCont = cancelledStreamCont
        }

        func wait() async throws -> Int? {
            var iterator = stream.makeAsyncIterator()
            while let value = await iterator.next() {
                if value == id {
                    cancelledStreamCont.yield(id)
                    return id
                }
            }
            return nil
        }
    }
}

/// The type is Sendable, I should upstream this though
///
/// Require for the merge
extension FileChange: @retroactive @unchecked Sendable {}
