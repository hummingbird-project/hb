import ArgumentParser
import Mustache
import Noora
import Subprocess
import SystemPackage
import ZipArchive

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct InitCommand: AsyncParsableCommand {
    enum TemplateFeature: String, CaseIterable, CustomStringConvertible {
        case openapi = "OpenAPI"
        case vscodeSnippets = "Visual Studio Code Snippets"

        var description: String { rawValue }
    }
    enum ApplicationType: String, CaseIterable, CustomStringConvertible {
        case server = "Server"
        case lambda = "Lambda"

        var description: String { rawValue }
    }
    enum LambdaType: String, CaseIterable, CustomStringConvertible {
        case apiGateway = "APIGateway"
        case apiGatewayV2 = "APIGatewayV2"
        case functionURL = "FunctionURL"

        var description: String { rawValue }
    }

    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize the hummingbird server."
    )

    @Argument(help: "Target folder (defaults to current folder)", completion: .directory)
    var targetFolder: String?

    @Flag(help: "Use default setup.")
    var `default`: Bool = false

    func run() async throws {
        // create target folder
        if let targetFolder {
            try FileManager.default.createDirectory(
                atPath: targetFolder,
                withIntermediateDirectories: true
            )
            _ = FileManager.default.changeCurrentDirectoryPath(targetFolder)
        }

        // get folder name
        let currentFolder = FilePath(FileManager.default.currentDirectoryPath)
        guard let currentFolderName = currentFolder.lastComponent?.description else {
            throw HBError("Could not get folder name")
        }

        if try FileManager.default.contentsOfDirectory(atPath: currentFolder.string).count != 0 {
            guard
                Noora().yesOrNoChoicePrompt(
                    question: "Your target folder is not empty. Do you want to continue?",
                    collapseOnSelection: true
                ) == true
            else {
                return
            }
        }

        var context = [
            "hbPackageName": currentFolderName,
            "hbExecutableName": "App",
        ]
        if !self.default {
            self.constructContext(&context)
        }

        // Get the latest version number of the template
        let templateVersion = try await getLatestTemplateVersion()

        print("Downloading template version \(templateVersion)")
        let zipReader = try await getTemplateZipArchive(version: templateVersion)

        print("Outputting to: \(currentFolder.description)")

        try generateProject(
            zipReader: zipReader,
            context: context
        )
    }

    func constructContext(_ context: inout [String: String]) {
        let applicationType: ApplicationType = Noora().singleChoicePrompt(
            question: "What kind of application are you building",
            options: [.server, .lambda]
        )
        let appName: String
        var lambdaType: LambdaType? = nil
        switch applicationType {
        case .server:
            let name = Noora().textPrompt(
                title: TerminalText("What would you like your executable to be named?"),
                prompt: TerminalText("App Name: "),
                validationRules: [
                    NonEmptyValidationRule(error: "App name cannot be empty."),
                    NoWhitespaceValidationRule(error: "App name cannot contain whitespace."),
                    AsciiValidationRule(error: "App name cannot contain non-ASCII characters."),
                ]
            )
            let firstLetter = name[name.startIndex].uppercased()
            appName = firstLetter + name.dropFirst()
        case .lambda:
            appName = "App"
            lambdaType = Noora().singleChoicePrompt(
                question: "What kind of lambda are you building",
                options: [.apiGateway, .apiGatewayV2, .functionURL]
            )
        }

        let choices = Noora().multipleChoicePrompt(
            question: TerminalText("Which features would you like to enable?"),
            options: TemplateFeature.allCases,
        )

        switch applicationType {
        case .server:
            context["hbExecutableName"] = appName
        case .lambda:
            context["hbLambda"] = "yes"
            context["hbLambdaType"] = lambdaType?.rawValue
        }
        if choices.contains(.openapi) {
            context["hbOpenAPI"] = "yes"
        }
        if choices.contains(.vscodeSnippets) {
            context["hbVSCodeSnippets"] = "yes"
        }
    }

    func getLatestTemplateVersion() async throws -> Version {
        try await Subprocess.run(
            .name("git"),
            arguments: [
                "ls-remote", "--refs", "--tags", "https://github.com/hummingbird-project/template",
            ],
            input: .none,
            output: .sequence,
            error: .discarded
        ) { execution in
            var versions: [Version] = []
            for try await line in execution.standardOutput.strings() {
                if let match = try? #/.*refs\/tags\/(.*)/#.wholeMatch(in: line) {
                    if let version = Version(match.output.1) {
                        versions.append(version)
                    }
                }
            }
            guard let version = versions.sorted().last else { throw HBError("Failed to get template version.") }
            return version
        }.closureOutput
    }

    func getTemplateZipArchive(
        version: Version
    ) async throws -> ZipArchiveReader<some ZipReadableStorage> {
        // download Zip file and open
        let templateZipArchiveData = try Data(
            contentsOf: URL(
                string:
                    "https://github.com/hummingbird-project/template/archive/refs/tags/\(version).zip"
            )!
        )
        return try ZipArchiveReader(buffer: templateZipArchiveData)
    }

    func generateProject(
        zipReader: ZipArchiveReader<some ZipReadableStorage>,
        context: [String: String]
    ) throws {
        let ignoreFiles: [FilePath] = [
            ".github/workflows/test-configure.yml",
            "configure.sh",
            "scripts/download.sh",
            "scripts/test_configure.sh",
        ]
        let directory = try zipReader.readDirectory()
        for file in directory {
            guard let rootComponent = file.filename.components.first else { continue }
            guard !file.isDirectory else { continue }

            // remove first directory from filename and verify we want this file
            var filename = file.filename
            guard filename.removePrefix(.init(rootComponent.description)) == true else {
                continue
            }
            guard filename.length > 0 else { continue }
            guard !ignoreFiles.contains(filename) else { continue }

            let contents = try zipReader.readFile(file)
            let template = try MustacheTemplate(
                string: String(decoding: contents, as: UTF8.self)
            )
            let result = template.render(context)
            if result.isEmpty {
                continue
            }

            let directoryName = filename.removingLastComponent()
            if directoryName.length > 0 {
                // create sub-directories for file
                try FileManager.default.createDirectory(
                    atPath: filename.removingLastComponent().description,
                    withIntermediateDirectories: true
                )
            }
            print("Creating file \(filename)")
            if FileManager.default.createFile(
                atPath: filename.description,
                contents: Data(result.utf8)
            ) == false {
                print("Failed to create \(file.filename.description)")
            }
        }
    }
}
