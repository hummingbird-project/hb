//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import ArgumentParser
import AsyncAlgorithms
import FileMonitor
import Logging
import ServiceLifecycle
import Subprocess
import Synchronization

#if canImport(System)
import System
#else
import SystemPackage
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct WatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch for changes to your application source code and re-build and run it."
    )

    @Flag(name: [.customShort("s"), .long], help: "Use swiftly to run swift processes")
    var useSwiftly: Bool = false

    @Flag(name: [.customShort("b"), .long], help: "Only build the executable.")
    var buildOnly: Bool = false

    @Flag(name: [.long], help: "Build tests as well as the executable.")
    var buildTests: Bool = false

    @Option(
        name: [.customShort("w"), .long],
        help: "Folders to watch. This defaults to \"Sources\", or \"Sources\" and \"Tests\" if the --build-tests option is enabled."
    )
    var watch: [String] = []

    @Argument(help: "The executable to build and run.")
    var product: String? = nil

    // The arguments to pass to the executable.
    @Argument(
        parsing: .captureForPassthrough,
        help: "The arguments to pass to the executable."
    )
    var arguments: [String] = []

    func run() async throws {
        let watchService = WatchService(self)
        let serviceGroup = ServiceGroup(services: [watchService], cancellationSignals: [.sigint, .sigterm], logger: Logger(label: "Watch"))
        try await serviceGroup.run()
    }
}

struct WatchService: Service {
    let watchFolders: [String]
    let useSwiftly: Bool
    let product: String?
    let arguments: [String]
    let buildOnly: Bool
    let buildTests: Bool

    var swiftPM: SwiftPM { .init(useSwiftly: self.useSwiftly) }

    init(_ command: WatchCommand) {
        self.useSwiftly = command.useSwiftly
        self.product = command.product
        self.arguments = command.arguments
        self.buildOnly = command.buildOnly
        self.buildTests = command.buildTests
        if command.watch.count == 0 {
            self.watchFolders = self.buildTests ? ["Sources", "Tests"] : ["Sources"]
        } else {
            self.watchFolders = command.watch
        }
    }

    func run() async throws {
        let currentDirectory = FileManager.default.currentDirectoryPath
        let fileMonitors = try self.watchFolders.map {
            let sourceDirectory = URL(filePath: currentDirectory, directoryHint: .isDirectory)
                .appending(path: $0, directoryHint: .isDirectory)
            return try FileMonitor(directory: sourceDirectory)
        }
        for monitor in fileMonitors {
            try monitor.start()
        }
        defer {
            for monitor in fileMonitors {
                monitor.stop()
            }
        }
        switch fileMonitors.count {
        case 1:
            try await run(fileMonitors[0].stream)
        case 2:
            try await run(merge(fileMonitors[0].stream, fileMonitors[1].stream))
        case 3:
            try await run(merge(fileMonitors[0].stream, fileMonitors[1].stream, fileMonitors[2].stream))
        default:
            throw HBError("hb only supports watching up to 3 folders.")
        }
    }

    func run(_ fileEvents: some AsyncSequence<FileChange, Never>) async throws {
        let targetProduct = try await self.swiftPM.getExecutableProduct(desiredProduct: self.product)
        let build = self.swiftPM.getCommand(["build", "--product", targetProduct])
        let run = try await SubprocessCommand(.path(self.swiftPM.getBinaryPath(product: targetProduct)), arguments: .init(arguments))

        await withTaskGroup { group in
            // Initial build and run
            var cancellationToken = addBuildAndRunTasks(
                build: build,
                run: run,
                group: &group
            )
            let throttledStream = fileEvents._throttle(for: .seconds(1)) { (result: Bool?, event: FileChange) in
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
                    // A file changed, yield a cancel request
                    cancellationToken.yield()
                    // wait for previous build/run task to finish
                    await group.next()
                    // start new build and run
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
            )
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
        if self.buildOnly || Task.isCancelled {
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

extension FileChange: @retroactive @unchecked Sendable {}
