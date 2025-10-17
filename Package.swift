// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "hb",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "hb", targets: ["hb"])
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/Noora.git", from: "0.49.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
        .package(url: "https://github.com/hummingbird-project/swift-mustache.git", from: "2.0.0"),
        .package(url: "https://github.com/adam-fowler/swift-zip-archive.git", from: "0.6.4"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.2.0", traits: []),
    ],
    targets: [
        .executableTarget(
            name: "hb",
            dependencies: [
                .product(name: "Noora", package: "Noora"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ZipArchive", package: "swift-zip-archive"),
                .product(name: "Mustache", package: "swift-mustache"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        )
    ]
)
