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

    func run() async throws {
        let targetProduct = try await self.swiftPM.getExecutableProduct(desiredProduct: self.product)
        let build = self.swiftPM.getCommand(["build", "--product", targetProduct])
        let run = try await SubprocessCommand(.path(self.swiftPM.getBinaryPath(product: targetProduct)), arguments: .init(arguments))

        let currentDirectory = FileManager.default.currentDirectoryPath
        let sourceDirectory = URL(filePath: currentDirectory, directoryHint: .isDirectory)
            .appending(path: "Sources", directoryHint: .isDirectory)
        let fileMonitor = try FileMonitor(directory: sourceDirectory)
        try fileMonitor.start()
        defer {
            fileMonitor.stop()
        }

        await withTaskGroup { group in
            // Initial build and run
            var cancellationToken = addBuildAndRunTasks(
                build: build,
                run: run,
                group: &group
            )
            let throttledStream = fileMonitor.stream._throttle(for: .seconds(1)) { (result: Bool?, event: FileChange) in
                switch event {
                case .changed(let file):
                    print("File changed \(file)")
                    return true
                default:
                    return result ?? false
                }
            }
            for await changed in throttledStream {
                if changed {
                    // A file changed, yield a cancel request and start a new build.
                    cancellationToken.yield()
                    await group.next()
                    cancellationToken = addBuildAndRunTasks(
                        build: build,
                        run: run,
                        group: &group
                    )
                }
            }

            group.cancelAll()
        }
    }

    /// Build target and once that has finished run the target
    func addBuildAndRunTasks(
        build: SubprocessCommand,
        run: SubprocessCommand,
        group: inout TaskGroup<Void>
    ) -> AsyncStream<Void>.Continuation {
        let (stream, cont) = AsyncStream.makeStream(of: Void.self)
        group.addTask {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await _addBuildAndRunTasks(build: build, run: run)
                }

                group.addTask {
                    await stream.first { _ in true }
                }
                await group.next()
                group.cancelAll()
            }
        }
        return cont
    }

    func _addBuildAndRunTasks(
        build: SubprocessCommand,
        run: SubprocessCommand,
    ) async {
        var platformOptions = PlatformOptions()
        platformOptions.teardownSequence = [
            .gracefulShutDown(allowedDurationToNextStep: .seconds(5))
        ]
        let result: ExecutionResult<Void, FileDescriptorOutput, FileDescriptorOutput>
        do {
            if Task.isCancelled {
                return
            }
            result = try await Subprocess.run(
                build.executable,
                arguments: build.arguments,
                platformOptions: platformOptions,
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
        if Task.isCancelled {
            return
        }
        do {
            _ = try await Subprocess.run(
                run.executable,
                arguments: run.arguments,
                platformOptions: platformOptions,
                input: .standardInput,
                output: .currentStandardOutput,
                error: .currentStandardError
            ) { execution in
                print("PID: \(execution.processIdentifier)")
            }
        } catch {
            print("\(error)")
        }
    }
}
