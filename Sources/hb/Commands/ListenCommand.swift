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

    var swiftPM: SwiftPM { .init(useSwiftly: self.useSwiftly) }

    func run() async throws {
        let targetProduct = try await self.swiftPM.getExecutableProduct(desiredProduct: self.product)
        let build = self.swiftPM.getCommand(["build", "--product", targetProduct])
        let run: (Executable, Arguments) = try await (.path(self.swiftPM.getBinaryPath(product: targetProduct)), [])

        try await withThrowingTaskGroup(of: Void.self) { group in
            let currentDirectory = FileManager.default.currentDirectoryPath
            let sourceDirectory = URL(filePath: currentDirectory, directoryHint: .isDirectory)
                .appending(path: "Sources", directoryHint: .isDirectory)
            let fileMonitor = try FileMonitor(directory: sourceDirectory)
            try fileMonitor.start()
            defer {
                fileMonitor.stop()
            }

            let (stream, cont) = AsyncStream.makeStream(of: Int.self)
            let (cancelledStream, cancelledCont) = AsyncStream.makeStream(of: Void.self)
            var globalID = 0
            building.store(true, ordering: .relaxed)
            addBuildAndRunTasks(
                build: build,
                run: run,
                group: &group,
                cancellation: SubProcessCancellation(globalID: &globalID, stream: stream, cancelledStreamCont: cancelledCont)
            )
            enum StreamEvent {
                case monitor(FileChange)
                case cancelledRun
            }
            let combinedStream = merge(fileMonitor.stream.map { StreamEvent.monitor($0) }, cancelledStream.map { .cancelledRun })
            for try await event in combinedStream {
                switch event {
                case .monitor(.changed(let file)):
                    // A file changed, should we trigger a new build.
                    print("File changed \(file)")
                    cont.yield(globalID)
                    guard building.compareExchange(expected: false, desired: true, ordering: .relaxed).original == false else {
                        continue
                    }
                    addBuildAndRunTasks(
                        build: build,
                        run: run,
                        group: &group,
                        cancellation: SubProcessCancellation(globalID: &globalID, stream: stream, cancelledStreamCont: cancelledCont)
                    )
                case .cancelledRun:
                    guard building.compareExchange(expected: false, desired: true, ordering: .relaxed).original == false else {
                        continue
                    }
                    addBuildAndRunTasks(
                        build: build,
                        run: run,
                        group: &group,
                        cancellation: SubProcessCancellation(globalID: &globalID, stream: stream, cancelledStreamCont: cancelledCont)
                    )
                default:
                    break
                }
            }

            group.cancelAll()
        }
    }

    /// Build target and once that has finished run the target
    func addBuildAndRunTasks(
        build: (exe: Executable, arguments: Arguments),
        run: (exe: Executable, arguments: Arguments),
        group: inout ThrowingTaskGroup<Void, any Error>,
        cancellation: SubProcessCancellation
    ) {
        let (stream, cont) = AsyncThrowingStream.makeStream(of: TerminationStatus.self)
        // Run build
        group.addTask {
            defer {
                building.store(false, ordering: .relaxed)
            }
            do {
                let result = try await Subprocess.run(
                    build.exe,
                    arguments: build.arguments,
                    input: .standardInput,
                    output: .currentStandardOutput,
                    error: .currentStandardError
                ) { execution in
                }
                cont.yield(result.terminationStatus)
            } catch {
                cont.finish()
            }
        }
        // Run executable
        group.addTask {
            // wait for build to complete
            var iterator = stream.makeAsyncIterator()
            switch try await iterator.next() {
            case .exited(let status):
                guard status == 0 else { return }
            default:
                return
            }

            do {
                _ = try await Subprocess.run(
                    run.exe,
                    arguments: run.arguments,
                    input: .standardInput,
                    output: .currentStandardOutput,
                    error: .currentStandardError
                ) { execution in
                    print("PID: \(execution.processIdentifier)")
                    if let id = try await cancellation.wait() {
                        print("Cancelling run: \(id)")
                        try execution.send(signal: .terminate)
                    }
                }
            } catch {
                print(error)
            }
        }
    }

    struct SubProcessCancellation: Sendable {
        let stream: AsyncStream<Int>
        let cancelledStreamCont: AsyncStream<Void>.Continuation
        let id: Int

        init(globalID: inout Int, stream: AsyncStream<Int>, cancelledStreamCont: AsyncStream<Void>.Continuation) {
            globalID += 1
            self.id = globalID
            self.stream = stream
            self.cancelledStreamCont = cancelledStreamCont
        }

        func wait() async throws -> Int? {
            var iterator = stream.makeAsyncIterator()
            while let value = await iterator.next() {
                if value == id {
                    cancelledStreamCont.yield()
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
