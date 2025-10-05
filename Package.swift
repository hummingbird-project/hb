// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "hb",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "hb", targets: ["hb"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/Noora.git", from: "0.49.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
    ],
    targets: [
        .executableTarget(
            name: "hb",
            dependencies: [
                .product(name: "Noora", package: "Noora"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        )
    ]
)