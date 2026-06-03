import ArgumentParser
import Foundation

@main
struct HB: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "HB is a tool for managing your Hummingbird server.",
        version: "0.1.0",
        subcommands: [
            InitCommand.self,
            RunCommand.self,
        ]
    )
}
