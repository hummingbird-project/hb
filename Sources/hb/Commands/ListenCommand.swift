import ArgumentParser
import Darwin.C
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

    @Option(name: .shortAndLong)
    var product: String? = nil

    @Flag(name: .shortAndLong)
    var useSwiftly: Bool = false

    var swiftPM: SwiftPM { .init(useSwiftly: self.useSwiftly) }

    func run() async throws {
        let executables = try await self.swiftPM.getExecutableProducts()
        let targetProduct: String
        if let product = self.product {
            guard executables.contains(product) else {
                throw HBError("Cannot find executable target \(product)")
            }
            targetProduct = product
        } else {
            guard executables.count != 0 else {
                throw HBError("Package has no executables products.")
            }
            guard executables.count == 1 else {
                throw HBError("Package has multiple executables. Please use \"--product\" to choose the executable you want to run.")
            }
            targetProduct = executables[0]
        }
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
            var globalID = 0
            building.store(true, ordering: .relaxed)
            addBuildAndRunTasks(
                build: build,
                run: run,
                group: &group,
                cancellation: SubProcessCancellation(globalID: &globalID, stream: stream)
            )
            for try await event in fileMonitor.stream {
                switch event {
                case .changed(let file):
                    print("File changed \(file)")
                    guard building.compareExchange(expected: false, desired: true, ordering: .relaxed).original == false else {
                        continue
                    }
                    cont.yield(globalID)
                    addBuildAndRunTasks(
                        build: build,
                        run: run,
                        group: &group,
                        cancellation: SubProcessCancellation(globalID: &globalID, stream: stream)
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
        group.addTask {
            defer {
                building.store(false, ordering: .relaxed)
            }
            do {
                let result = try await Subprocess.run(
                    build.exe,
                    arguments: build.arguments,
                    input: .standardInput,
                    output: .standardOutput,
                    error: .standardError
                ) { execution in
                }
                cont.yield(result.terminationStatus)
            } catch {
                cont.finish()
            }
        }
        group.addTask {
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
                    output: .standardOutput,
                    error: .standardError
                ) { execution in
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

    func addSubProcessTask(
        name: String,
        arguments: [String],
        group: inout ThrowingTaskGroup<Void, any Error>,
        cancellation: SubProcessCancellation?
    ) {
        group.addTask {
            _ = try await Subprocess.run(
                .name(name),
                arguments: .init(arguments),
                input: .standardInput,
                output: .standardOutput,
                error: .standardError
            ) { execution in
                if let id = try await cancellation?.wait() {
                    print("Cancelling run: \(id)")
                    try execution.send(signal: .terminate)
                }
            }
        }
    }

    struct SubProcessCancellation: Sendable {
        let stream: AsyncStream<Int>
        let id: Int

        init(globalID: inout Int, stream: AsyncStream<Int>) {
            globalID += 1
            self.id = globalID
            self.stream = stream
        }

        func wait() async throws -> Int? {
            var iterator = stream.makeAsyncIterator()
            while let value = await iterator.next() {
                if value == id {
                    return id
                }
            }
            return nil
        }
    }
}
