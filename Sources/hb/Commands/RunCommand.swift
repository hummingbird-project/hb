import ArgumentParser
import Subprocess

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Build and run your application."
    )

    @Flag(name: [.customShort("s"), .long], help: "Use swiftly to run swift processes")
    var useSwiftly: Bool = false

    @Argument(help: "The executable to run.")
    var product: String? = nil

    var swiftPM: SwiftPM { .init(useSwiftly: self.useSwiftly) }

    func run() async throws {
        let targetProduct = try await self.swiftPM.getExecutableProduct(desiredProduct: self.product)
        let arguments = ["run", targetProduct]
        let command = swiftPM.getCommand(arguments)
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
