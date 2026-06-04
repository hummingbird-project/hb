import ArgumentParser
import Subprocess

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build your application."
    )

    @Option(name: .shortAndLong)
    var product: String? = nil

    @Flag(name: .shortAndLong)
    var useSwiftly: Bool = false

    var swiftPM: SwiftPM { .init(useSwiftly: self.useSwiftly) }

    func run() async throws {
        var arguments = ["build"]
        if let product {
            arguments.append(contentsOf: ["--product", product])
        }
        let command = self.swiftPM.getCommand(arguments)
        _ = try await Subprocess.run(
            command.exe,
            arguments: command.arguments,
            input: .none,
            output: .currentStandardOutput,
            error: .currentStandardError
        ) { _ in
        }
    }
}
