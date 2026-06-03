import ArgumentParser
import Darwin.C
import Subprocess

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build your application."
    )

    @Option(name: .shortAndLong)
    var product: String? = nil

    func run() async throws {
        var arguments = ["build"]
        if let product {
            arguments.append(contentsOf: ["--product", product])
        }
        _ = try await Subprocess.run(
            .name("swift"),
            arguments: .init(arguments),
            input: .none,
            output: .standardOutput,
            error: .standardError
        ) { _ in
        }
    }
}
