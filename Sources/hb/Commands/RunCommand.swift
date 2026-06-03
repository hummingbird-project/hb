import ArgumentParser
import Darwin.C
import Subprocess

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Build and run your application."
    )

    func run() async throws {
        _ = try await Subprocess.run(
            .name("swift"),
            arguments: [
                "run"
            ],
            input: .none,
            output: .standardOutput,
            error: .standardError
        ) { _ in
        }
    }
}
