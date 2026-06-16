// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "hb",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "hb", targets: ["hb"])
    ],
    dependencies: [
        .package(url: "https://github.com/adam-fowler/swift-zip-archive.git", from: "0.8.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.100.0"),
        .package(url: "https://github.com/aus-der-Technik/FileMonitor.git", from: "1.2.0"),
        .package(url: "https://github.com/hummingbird-project/swift-mustache.git", from: "2.0.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.5.0", traits: []),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.34.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        .package(url: "https://github.com/tuist/Noora.git", from: "0.56.0"),
    ],
    targets: [
        .executableTarget(
            name: "hb",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "FileMonitor", package: "FileMonitor"),
                .product(name: "Mustache", package: "swift-mustache"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "Noora", package: "Noora"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "ZipArchive", package: "swift-zip-archive"),
            ]
        )
    ]
)
