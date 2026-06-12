//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import ArgumentParser
import AsyncHTTPClient
import Mustache
import NIOFoundationCompat
import Noora
import Subprocess
import SystemPackage
import ZipArchive

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize the hummingbird server."
    )

    @Argument(help: "Target folder (defaults to current folder)", completion: .directory)
    var targetFolder: String?

    @Flag(help: "Use default setup.")
    var `default`: Bool = false

    @Option(help: "Path to custom template folder or git repository.")
    var template: String = "https://github.com/hummingbird-project/template"

    func run() async throws {
        let startFolder = FilePath(FileManager.default.currentDirectoryPath)
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

        let context = [
            "hbPackageName": currentFolderName,
            "hbExecutableName": "App",
        ]
        if template.hasPrefix("http://") || template.hasPrefix("https://") || template.hasPrefix("git@") {
            // Get the latest version number of the template
            let templateVersion = try await getLatestTemplateVersion()

            print("Downloading template version \(templateVersion)")
            let zipReader = try await getTemplateZipArchive(repository: self.template, version: templateVersion)

            print("Outputting to: \(currentFolder.description)")

            try generateProject(
                zipReader: zipReader,
                context: context
            )
        } else {
            var filePath = FilePath(self.template)
            if filePath.isRelative {
                filePath = startFolder.pushing(filePath)
                filePath = filePath.lexicallyNormalized()
            }

            let zipReader = try createZipFromFolder(filePath)

            print("Outputting to: \(currentFolder.description)")

            try generateProject(
                zipReader: zipReader,
                context: context
            )
        }
    }

    func getLatestTemplateVersion() async throws -> Version {
        try await Subprocess.run(
            .name("git"),
            arguments: [
                "ls-remote", "--refs", "--tags", self.template,
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
        repository: String,
        version: Version
    ) async throws -> ZipArchiveReader<some ZipReadableStorage> {
        // download Zip file and open
        let url =
            if repository.hasSuffix(".git") {
                repository.dropLast(4)
            } else {
                repository[...]
            }
        let response = try await HTTPClient.shared.get(url: "\(url)/archive/refs/tags/\(version).zip").get()
        guard let responseBody = response.body else { throw HBError("Failed to download release \(version)") }
        return try ZipArchiveReader(buffer: Data(buffer: responseBody))
    }

    func createZipFromFolder(_ folder: FilePath) throws -> ZipArchiveReader<some ZipReadableStorage> {
        let zipArchiveWriter = ZipArchiveWriter()
        try zipArchiveWriter.writeFolderContents(
            folder,
            options: [.recursive, .includeContainingFolder, .includeHiddenFiles]
        ) { file, isDirectory in
            // don't include SwiftPM build folder or the git folder
            file.lastComponent != ".build" && file.lastComponent != ".git"
        }
        let buffer = try zipArchiveWriter.finalizeBuffer()
        return try ZipArchiveReader(buffer: buffer)
    }

    func generateProject(
        zipReader: ZipArchiveReader<some ZipReadableStorage>,
        context: [String: String]
    ) throws {
        var context = context
        let ignoreFiles: [FilePath] = [
            ".github/workflows/test-configure.yml",
            "configure.sh",
            "scripts/download.sh",
            "scripts/test_configure.sh",
            "metadata.json",
        ]
        let directory = try zipReader.readDirectory()

        // Get metadata.json and build template definition
        guard let metadataJsonEntry = directory.first(where: { $0.filename.lastComponent == "metadata.json" }) else {
            throw HBError("Failed to find template metadata.")
        }
        let metadataJson = try zipReader.readFile(metadataJsonEntry)
        let templateDefinition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(metadataJson))
        // construct context from template definition
        if !self.default {
            try templateDefinition.constructContext(&context)
        }

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
            // remove mustache extension
            if filename.extension == "mustache", let stem = filename.stem {
                filename = filename.removingLastComponent().appending(stem)
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
