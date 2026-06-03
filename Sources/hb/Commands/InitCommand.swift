import ArgumentParser
import Foundation
import Mustache
import Noora
import Subprocess
import SystemPackage
import ZipArchive

struct InitCommand: AsyncParsableCommand {
    enum TemplateFeature: String, CaseIterable, CustomStringConvertible {
        case openapi = "OpenAPI"
        case vscodeSnippets = "Visual Studio Code Snippets"

        var description: String { rawValue }
    }

    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize the hummingbird server."
    )

    @Option(help: "Target folder (defaults to current folder)", completion: .directory)
    var targetFolder: String?

    func run() async throws {
        enum AppType {
            case server
            case lambda(String)
        }
        let path = URL(string: FileManager.default.currentDirectoryPath)!.appending(path: "example")
        print("Outputting to: \(path.path())")

        var name = Noora().textPrompt(
            title: TerminalText("What project name would you like to use?"),
            prompt: TerminalText("App Name: "),
            description: TerminalText("The name of the project you want to create."),
            validationRules: [
                NonEmptyValidationRule(error: "App name cannot be empty."),
                NoWhitespaceValidationRule(error: "App name cannot contain whitespace."),
                AsciiValidationRule(error: "App name cannot contain non-ASCII characters."),
            ]
        )
        let firstLetter = name[name.startIndex].uppercased()
        name = firstLetter + name.dropFirst()

        let appType: AppType =
            if Noora().singleChoicePrompt(
                question: "What kind of application are you building",
                options: ["server", "lambda"]
            ) == "lambda" {
                .lambda(
                    Noora().singleChoicePrompt(
                        question: "What kind of lambda are you building",
                        options: ["APIGateway", "APIGatewayV2", "FunctionURL"])
                )
            } else {
                .server
            }

        let choices = Noora().multipleChoicePrompt(
            question: TerminalText("Which features would you like to enable?"),
            options: TemplateFeature.allCases,
        )

        let templateVersion = try await getLatestTemplateVersion()

        // create target folder
        if let targetFolder {
            try FileManager.default.createDirectory(
                atPath: targetFolder, withIntermediateDirectories: true)
            FileManager.default.changeCurrentDirectoryPath(targetFolder)
        }

        // get folder name
        let currentFolder = FilePath(FileManager.default.currentDirectoryPath)
        guard let currentFolderName = currentFolder.lastComponent?.description else {
            throw HBError("Could not get folder name")
        }

        print("Downloading template version \(templateVersion)")
        let zipReader = try await getTemplateZipArchive(version: templateVersion)

        var context = [
            "hbExecutableName": name,
            "hbPackageName": currentFolderName,
        ]
        switch appType {
        case .server:
            break
        case .lambda(let type):
            context["hbLambda"] = "yes"
            context["hbLambdaType"] = type
        }
        if choices.contains(.openapi) {
            context["hbOpenAPI"] = "yes"
        }
        if choices.contains(.vscodeSnippets) {
            context["hbVSCodeSnippets"] = "yes"
        }
        try generateProject(
            zipReader: zipReader,
            context: context
        )
    }

    func getLatestTemplateVersion() async throws -> Version {
        try await Subprocess.run(
            .name("git"),
            arguments: [
                "ls-remote", "--refs", "--tags", "https://github.com/hummingbird-project/template",
            ]
        ) { execution, stdout in
            var versions: [Version] = []
            for try await line in stdout.lines() {
                if let match = try? #/.*refs\/tags\/(.*)\n/#.wholeMatch(in: line) {
                    if let version = Version(match.output.1) {
                        versions.append(version)
                    }
                }
            }
            return versions.sorted().last!
        }.value
    }

    func getTemplateZipArchive(version: Version) async throws -> ZipArchiveReader<
        some ZipReadableStorage
    > {
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
        zipReader: ZipArchiveReader<some ZipReadableStorage>, context: [String: String]
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
            guard filename.removePrefix(FilePath(rootComponent.description)) == true else {
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
                    withIntermediateDirectories: true)
            }
            print("Creating file \(filename)")
            if FileManager.default.createFile(
                atPath: filename.description, contents: Data(result.utf8)) == false
            {
                print("Failed to create \(file.filename.description)")
            }
        }
    }
}
