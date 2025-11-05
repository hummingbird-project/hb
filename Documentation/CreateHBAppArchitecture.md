# CreateHBApp Architecture

CreateHBApp is a Swift CLI that scaffolds a Hummingbird project based on user-selected templates and features. The architecture centers everything around a `ProjectBlueprint` that template and feature modules contribute to.

## High-Level Flow

```
+-------------------+           +-------------------+
|  CLI (CreateHBApp)|---------->|    InitWorkflow   |
+---------+---------+           +----------+--------+
          |                               |
          | uses                           | resolves modules
          v                               v
+-------------------+           +-------------------+
|   InputProvider   |           | TemplateCatalog   |
| (Prompts/Flags)   |           | FeatureCatalog    |
+---------+---------+           +-------------------+
          | answers                         |
          v                                 |
+-------------------+           +-------------------+
| ProjectBlueprint  |<----------| Template &        |
|    Builder        |  apply    | Feature modules   |
+---------+---------+           +-------------------+
          | build blueprint
          v
+-------------------+
|  ProjectBlueprint |
+---------+---------+
          | render
          v
+-------------------+
|  TemplateEngine   |
|  OutputServices   |
+-------------------+
```

## Core Components

- **CLI (`CreateHBApp`, `InitCommand`)**  
  Parses arguments and invokes `InitWorkflow`. No file generation occurs here.

- **InitWorkflow**  
  Central coordinator with three responsibilities:
  1. Gather inputs via an `InputProvider`.
  2. Resolve the appropriate template and feature modules from catalogs.
  3. Build a `ProjectBlueprint` and render it through output services.

- **InputProvider**  
  Protocol supporting interactive prompts (Noora-backed) or scripted answers. Example signature:
  ```swift
  protocol InputProvider {
      func requestProjectConfiguration() async throws -> ProjectConfiguration
  }
  ```

- **TemplateCatalog / FeatureCatalog**  
  Lightweight registries mapping IDs to module implementations. Features declare prerequisites with `dependsOn`.
  ```swift
  protocol TemplateCatalog {
      func module(for id: TemplateID) throws -> BlueprintModule
  }

  protocol FeatureCatalog {
      func modules(for ids: [FeatureID]) throws -> [BlueprintModule]
  }
  ```
  Example concrete catalog:
  ```swift
  struct DefaultTemplateCatalog: TemplateCatalog {
      private let templates: [TemplateID: BlueprintModule] = [
          TemplateID("http-server"): HTTPServerTemplateModule(),
          TemplateID("lambda"): LambdaTemplateModule()
      ]

      func module(for id: TemplateID) throws -> BlueprintModule {
          guard let module = templates[id] else {
              throw CatalogError.unknownTemplate(id)
          }
          return module
      }
  }

  struct DefaultFeatureCatalog: FeatureCatalog {
      private let features: [FeatureID: BlueprintModule] = [
          FeatureID("login"): LoginFeatureModule(),
          FeatureID("postgres"): PostgresFeatureModule(),
          FeatureID("websocket"): WebSocketFeatureModule()
      ]

      func modules(for ids: [FeatureID]) throws -> [BlueprintModule] {
          try ids.map { id in
              guard let module = features[id] else {
                  throw CatalogError.unknownFeature(id)
              }
              return module
          }
      }
  }
  ```

- **BlueprintModule**  
  Shared interface for templates and features.
  ```swift
  protocol BlueprintModule {
      var id: ModuleID { get }
      var dependsOn: [ModuleID] { get }
      func apply(using builder: ProjectBlueprintBuilder,
                 configuration: ProjectConfiguration) throws
  }
  ```

- **ProjectBlueprintBuilder**  
  Aggregates contributions into a single blueprint.
  ```swift
  final class ProjectBlueprintBuilder {
      private var files: [GeneratedFile] = []
      private var package: PackageDescriptionEdit = .empty

      func addFile(_ file: GeneratedFile)
      func merge(_ dependency: PackageDependency)

      func build() -> ProjectBlueprint {
          ProjectBlueprint(files: files,
                           package: package)
      }
  }
  ```

- **GeneratedFile / PackageDescriptionEdit**  
  Utility types backing the builder:
  ```swift
  struct GeneratedFile {
      var path: RelativePath
      var contents: FileContents   // .static(String) or .templated(resource: String, tokens: [String: String])
  }

  struct PackageDescriptionEdit {
      var dependencies: [PackageDependency]
      var targetDependencies: [TargetDependency]
      static let empty = PackageDescriptionEdit(dependencies: [], targetDependencies: [])
  }
  ```

- **ProjectBlueprint**  
  Immutable snapshot describing all generated files and manifest edits. It owns the render step.
  ```swift
  struct ProjectBlueprint {
      var files: [GeneratedFile]
      var package: PackageDescriptionEdit

      func render(using engine: TemplateEngine,
                  outputs: OutputServices,
                  at path: URL) throws
  }
  ```

- **TemplateEngine**  
  Handles token replacement and simple iteration in resource templates. Resources live alongside the executable as SwiftPM bundle assets.

- **OutputServices**  
  Thin wrappers around filesystem and manifest operations:
  ```swift
  protocol OutputServices {
      var fileWriter: FileWriter { get }
      var packageWriter: PackageManifestWriter { get }
      var logger: PostCreateLogger { get }
  }
  ```

## Detailed Workflow

1. `InitCommand.run()` constructs `InitWorkflow` and calls `execute()`.
2. `InitWorkflow` obtains `ProjectConfiguration` from `InputProvider` (interactive or scripted).
3. Using the catalogs, it resolves the template module and each requested feature module. The workflow topologically sorts modules based on `dependsOn`; missing prerequisites produce a user-facing error.
4. A fresh `ProjectBlueprintBuilder` is created. The template module’s `apply` runs first to seed base files and dependencies. Each feature module then runs and augments the builder through the small API.
   Example: HTTP server template with Postgres feature
   - `HTTPServerTemplateModule.apply` executes first and calls:
     ```swift
     builder.addFile(.templated("Package.swift.hb", tokens: ["moduleName": config.name]))
     builder.addFile(.templated("Sources/App.swift.hb", tokens: ["moduleName": config.name]))
     builder.merge(.dependency(url: "https://github.com/apple/swift-argument-parser.git",
                               from: "1.6.1"))
     ```
     Example `Sources/App.swift.hb` resource template:
     ```swift
     import Hummingbird
     import Logging

     @main
     struct {{moduleName}}App {
         static func main() async throws {
             let logger = Logger(label: "{{moduleName}}")
             let app = try await buildApplication(logger: logger)
             try await app.runService()
         }
     }
     ```
   - `PostgresFeatureModule.apply` follows and contributes:
     ```swift
     builder.merge(.dependency(url: "https://github.com/vapor/postgres-kit.git",
                               from: "2.20.0"))
     builder.addFile(.templated("Sources/Database/PostgresService.swift.hb",
                                tokens: ["connectionEnv": "POSTGRES_URL"]))
     ```
   After both modules run, the builder contains the combined files and dependencies needed for the selected configuration.
5. `builder.build()` returns a `ProjectBlueprint`.
6. The blueprint calls `render(...)`, delegating template substitution to `TemplateEngine` and filesystem/manifest writes to `OutputServices`.
7. After rendering, `InitWorkflow` reports success (e.g., prints the project path) and exits.
