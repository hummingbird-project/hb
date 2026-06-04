import ArgumentParser
import Subprocess

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Build and run your application."
    )

    @Option(name: .shortAndLong)
    var product: String? = nil

    @Flag(name: .shortAndLong)
    var useSwiftly: Bool = false

    var swiftPM: SwiftPM { .init(useSwiftly: self.useSwiftly) }

    func run() async throws {
        var arguments = ["run"]
        if let product {
            arguments.append(contentsOf: ["--product", product])
        }
        let command = swiftPM.getCommand(arguments)
        _ = try await Subprocess.run(
            command.exe,
            arguments: command.arguments,
            input: .none,
            output: .standardOutput,
            error: .standardError
        ) { _ in
        }
    }
}
