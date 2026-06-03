import ArgumentParser
import Foundation

@main
struct HB: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "HB is for creating and managing hummingbird applications.",
        version: "1.0.0",
        subcommands: [
            InitCommand.self,
            BuildCommand.self,
            RunCommand.self,
        ]
    )
}
