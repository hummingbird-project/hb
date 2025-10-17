import ArgumentParser
import Noora
import Foundation

struct NoWhitespaceValidationRule: ValidatableRule {
    let error: any ValidatableError
    
    func validate(input: String) -> Bool {
        return !input.contains(where: \.isWhitespace)
    }
}

struct AsciiValidationRule: ValidatableRule {
    let error: any ValidatableError
    
    func validate(input: String) -> Bool {
        return !input.contains(where: { !$0.isASCII })
    }
}

@main
struct HB: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "HB is a tool for managing your hummingbird server.",
        version: "1.0.0",
        subcommands: [
            InitCommand.self,
        ]
    )
}

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize the hummingbird server."
    )

    func run() async throws {
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

        let choices = Noora().multipleChoicePrompt(
            question: TerminalText("Which features would you like to enable?"),
            options: TemplateFeature.allCases,
        )

        try FileManager.default.createDirectory(atPath: path.path(), withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(atPath: path.appending(path: "Sources").path(), withIntermediateDirectories: true, attributes: nil)

        FileManager.default.changeCurrentDirectoryPath(path.path())

        try generatePackageSwift(name: name, features: choices)
            .write(toFile: "Package.swift", atomically: true, encoding: .utf8)

        try generateEntryPoint(name: name, features: choices)
            .write(toFile: "Sources/EntryPoint.swift", atomically: true, encoding: .utf8)

        try generateBuildApplicationSwift(name: name, features: choices)
            .write(toFile: "Sources/Application.swift", atomically: true, encoding: .utf8)

        try generateAppRequestContextsSwift(name: name, features: choices)
            .write(toFile: "Sources/AppRequestContexts.swift", atomically: true, encoding: .utf8)

        try generateAddRoutesSwift(features: choices)
            .write(toFile: "Sources/Routes.swift", atomically: true, encoding: .utf8)

        if choices.contains(.login) {
            try generateJWT(name: name)
                .write(toFile: "Sources/JWT.swift", atomically: true, encoding: .utf8)
        }

        let models = generateModelsSwift(features: choices)
        for (fileName, contents) in models {
            try contents
            .write(toFile: "Sources/\(fileName)", atomically: true, encoding: .utf8)
        }
    }
}

func generateEntryPoint(
    name: String,
    features: [TemplateFeature]
) -> String {
    return """
    import ArgumentParser
    import Hummingbird

    @main
    struct \(name)EntryPoint: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "\(name)",
            abstract: "The entry point for the \(name) server."
        )

        func run() async throws {
            let app = try await buildApplication()
            try await app.runService()
        }
    }
    """
}

func featureAppRequestContextProperties(
    name: String,
    features: [TemplateFeature]
) -> [String: String] {
    var properties = [String: String]()

    for feature in features {
        switch feature {
        case .login:
            properties["identity"] = "User?"
            properties["token"] = "\(name)Payload?"
        case .otel, .websocket:
            continue
        }
    }

    return properties
}

func generateAppRequestContextsSwift(
    name: String,
    features: [TemplateFeature]
) -> String {
    let properties = featureAppRequestContextProperties(
        name: name,
        features: features
    )

    let variableDeclarations = properties.map { key, value in
        "    var \(key): \(value)"
    }.joined(separator: "\n")
    let setup = properties.map { key, value in
        "        self.\(key) = nil"
    }.joined(separator: "\n")

    var conformances = ["RequestContext"]
    if features.contains(.login) {
        conformances.append("AuthRequestContext")
    }

    return """
    import Hummingbird
    import HummingbirdCore
    import Logging
    \(generateImports(features: features))

    struct AppRequestContext: \(conformances.joined(separator: ", ")) {
        var coreContext: CoreRequestContextStorage
    \(variableDeclarations)
        
        init(source: ApplicationRequestContextSource) {
            self.coreContext = .init(source: source)
    \(setup)
        }
    }

    \(generateWebSocketAppRequestContextSwift(name: name, features: features))
    """
}

func generateModelsSwift(
    features: [TemplateFeature]
) -> [String: String] {
    let userModel = """
    #if canImport(FoundationEssentials)
    import FoundationEssentials
    #else
    import Foundation
    #endif

    struct User: Codable {
        let id: UUID
        var username: String
        var password: String
    }
    """

    return [
        "User.swift": userModel,
    ]
}

func generateWebSocketAppRequestContextSwift(
    name: String,
    features: [TemplateFeature]
) -> String {
    let properties = featureAppRequestContextProperties(
        name: name,
        features: features
    )

    let variableDeclarations = properties.map { key, value in
        "    var \(key): \(value)"
    }.joined(separator: "\n")
    let setup = properties.map { key, value in
        "        self.\(key) = nil"
    }.joined(separator: "\n")

    var conformances = ["RequestContext"]
    if features.contains(.login) {
        conformances.append("AuthRequestContext")
    }

    return """
    struct WebSocketAppRequestContext: WebSocketRequestContext, \(conformances.joined(separator: ", ")) {
        var coreContext: CoreRequestContextStorage
        let webSocket: WebSocketHandlerReference<Self>
        let logger = Logger(label: "websocket")
    \(variableDeclarations)

        init(source: ApplicationRequestContextSource) {
            self.coreContext = .init(source: source)
            self.webSocket = .init()
    \(setup)
        }
    }
    """
}

func generateAddRoutesSwift(
    features: [TemplateFeature]
) -> String {
    let loginContext = """
    struct AppAuthRequestContext: ChildRequestContext {
        var coreContext: CoreRequestContextStorage
        let user: User

        init(context: AppRequestContext) throws {
            self.coreContext = context.coreContext
            self.user = try context.requireIdentity()
        }
    }
    """

    let loginRoutes = """
        let authenticated = unauthenticated
            .add(middleware: try await JWTMiddleware())
            .group(context: AppAuthRequestContext.self)
    """

    let webSocketRoutes = """
    func addWebSocketRoutes(
        _ wsRouter: Router<WebSocketAppRequestContext>
    ) {
        wsRouter.ws { inbound, outbound, context in
            // Example: Echo the input back   
            for try await message in inbound {
                switch message.opcode {
                case .text:
                    let string = String(buffer: message.data)
                    try await outbound.write(.text(string))
                case .binary:
                    try await outbound.write(.binary(message.data))
                case .continuation:
                    try await outbound.write(.binary(message.data))
                }
            }
        }
    }
    """
    
    return """
    import Configuration
    import Hummingbird
    import Logging
    \(generateImports(features: features))

    \(features.contains(.login) ? loginContext : "")
    
    func addRoutes(
        _ routes: Router<AppRequestContext>
    ) async throws {
        let unauthenticated = routes.group("/api/v1")
    \(features.contains(.login) ? loginRoutes : "")
        // TODO: Add routes
    }

    \(features.contains(.websocket) ? webSocketRoutes : "")
    """
}


func generateBuildApplicationSwift(
    name: String,
    features: [TemplateFeature]
) -> String {
    return """
    import Configuration
    import Hummingbird
    import Logging
    import HummingbirdCore
    import ServiceLifecycle
    \(generateImports(features: features))

    let config = ConfigReader(providers: [
        CommandLineArgumentsProvider(),
        EnvironmentVariablesProvider(),
    ])

    func buildServices() async throws -> [any Service] {
    \(generateServices(name: name, features: features))
    }

    func buildApplication() async throws -> some ApplicationProtocol {
        let logger = Logger(label: "\(name)")

    \(generateServerImplementation(features: features))

        let router = Router(context: AppRequestContext.self)
        
        router.middlewares.add(TracingMiddleware())
        router.middlewares.add(MetricsMiddleware())
        router.middlewares.add(LogRequestsMiddleware(.info))

        try await addRoutes(router)

        var app = Application(
            router: router,
            server: server,
            configuration: .init(
                address: .hostname(
                    config.string(forKey: "http.hostname", default: "localhost"),
                    port: config.int(forKey: "http.port", default: 8080)
                )
            ),
            logger: logger,
        )

        for service in try await buildServices() {
            app.addServices(service)
        }

        return app
    }
    """
}

func generateJWT(name: String) -> String {
    return """
    import JWTKit
    import Hummingbird

    struct \(name)Payload: JWTPayload {
        var sub: SubjectClaim
        var exp: ExpirationClaim

        func verify(using key: some JWTAlgorithm) throws {
            try self.exp.verifyNotExpired()
        }
    }

    struct JWTMiddleware: RouterMiddleware {
        typealias Context = AppRequestContext
        let keys = JWTKeyCollection()
        
        init() async throws {
            #if DEBUG
            await keys.add(
                hmac: HMACKey(from: config.string(forKey: "jwt.secret", default: "<replace-in-production>")),
                digestAlgorithm: .sha256
            )
            #else
            try await keys.add(
                hmac: HMACKey(from: config.requiredString(forKey: "jwt.secret")),
                digestAlgorithm: .sha256
            )
            #endif
        }

        func handle(
            _ request: Request,
            context: AppRequestContext,
            next: (Request, AppRequestContext) async throws -> Response
        ) async throws -> Response {
            var context = context
            if let token = request.headers.bearer?.token {
                let jwt = try await keys.verify(token, as: \(name)Payload.self)
                context.token = jwt
            }
            
            return try await next(request, context)
        }
    }
    """
}

func generateServices(
    name: String,
    features: [TemplateFeature]
) -> String {
    var services = """
        var services = [any Service]()
    """

    for feature in features {
        switch feature {
        case .websocket, .login, .lambda:
            continue
        case .otel:
            services.append("""
            
                var otelConfig = OTel.Configuration.default
                otelConfig.serviceName = "\(name) Server"
                // To get started, we'll use the console exporter so you can see your logs in the terminal
                // Remove this in production, and set up Open Telemetry to send your logs to a real collector
                otelConfig.logs.exporter = .console
            """)
            services.append("\n    services.append(try OTel.bootstrap(configuration: otelConfig))")
        }
    }

    return """
    \(services)
        return services
    """
}

func generateServerImplementation(
    features: [TemplateFeature]
) -> String {
    if features.contains(.websocket) {
        return """
            let wsRouter = Router(context: WebSocketAppRequestContext.self)
            addWebSocketRoutes(wsRouter)

            let server = HTTPServerBuilder.http1WebSocketUpgrade(
                webSocketRouter: wsRouter
            )
        """
    }

    return """
        let server = HTTPServerBuilder.http1()
    """
}

func generatePackageSwift(
    name: String,
    features: [TemplateFeature]
) -> String {
    var dependencies = [String: String]()
    var targetDependencies = [String: String]()
    for feature in features {
        dependencies.merge(feature.dependencies, uniquingKeysWith: { $1 })
        targetDependencies.merge(feature.targetDependencies, uniquingKeysWith: { $1 })
    }
    
    let dependenciesString = dependencies.map {
        "        .package(url: \"\($0)\", from: \"\($1)\")"
    }.joined(separator: ",\n")

    let targetDependenciesString = targetDependencies.map {
        "                .product(name: \"\($0)\", package: \"\($1)\")"
    }.joined(separator: ",\n")

    return """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
        name: "\(name)",
        platforms: [
            .macOS(.v15)
        ],
        products: [
            .executable(name: "\(name)\", targets: ["\(name)\"]),
        ],
        dependencies: [
            .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
            .package(url: "https://github.com/apple/swift-configuration", .upToNextMinor(from: "0.1.0"), traits: [
                .defaults,
                "CommandLineArgumentsSupport",
            ]),
    \(dependenciesString)
        ],
        targets: [
            .executableTarget(
                name: "\(name)",
                dependencies: [
                    .product(name: "ArgumentParser", package: "swift-argument-parser"),
                    .product(name: "Configuration", package: "swift-configuration"),
    \(targetDependenciesString)
                ]
            )
        ]
    )
    """
}

func generateImports(features: [TemplateFeature]) -> String {
    let imports = Set(features.flatMap(\.imports))
    return imports.map {
        "import \($0)"
    }.joined(separator: "\n")
}

enum TemplateFeature: String, CaseIterable, CustomStringConvertible {
    case websocket = "WebSocket Server"
    case otel = "Open Telemetry"
    case login = "Login Flow"
    case lambda = "AWS Lambda"

    var description: String { rawValue }
    init?(description: String) {
        guard let feature = TemplateFeature(rawValue: description) else {
            return nil
        }
        self = feature
    }

    public var imports: [String] {
        switch self {
        case .websocket:
            return [
                "HummingbirdWebSocket",
            ]
        case .otel:
            return [
                "OTel",
            ]
        case .login:
            return [
                "JWTKit",
                "HummingbirdAuth",
                "HummingbirdBcrypt",
                "HummingbirdOTP",
            ]
        case .lambda:
            return [
                "HummingbirdLambda",
            ]
        }
    }

    public var targetDependencies: [String: String] {
        switch self {
        case .websocket:
            return [
                "HummingbirdWebSocket": "hummingbird-websocket",
            ]
        case .otel:
            return [
                "OTel": "swift-otel",
            ]
        case .login:
            return [
                "JWTKit": "jwt-kit",
                "HummingbirdAuth": "hummingbird-auth",
                "HummingbirdBcrypt": "hummingbird-auth",
                "HummingbirdOTP": "hummingbird-auth",
            ]
        case .lambda:
            return [
                "HummingbirdLambda": "hummingbird-lambda",
            ]
        }
    }

    public var dependencies: [String: String] {
        switch self {
        case .websocket:
            return [
                "https://github.com/hummingbird-project/hummingbird-websocket.git": "2.6.0",
            ]
        case .otel:
            return [
                "https://github.com/swift-otel/swift-otel.git": "1.0.0",
            ]
        case .login:
            return [
                "https://github.com/vapor/jwt-kit.git": "5.2.0",
                "https://github.com/hummingbird-project/hummingbird-auth.git": "2.0.2",
            ]
        case .lambda:
            return [
                "https://github.com/hummingbird-project/hummingbird-lambda.git": "2.0.0",
            ]
        }
    }
}
