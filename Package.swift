// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bestasr",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "bestasr", targets: ["bestasr"]),
        .executable(name: "bestasr-mcp", targets: ["bestasr-mcp"]),
        .library(name: "BestASRKit", targets: ["BestASRKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        // #25 diarization — exact pin per supply-chain discipline (design D3)
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.4"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // #80 MCP surface — same SDK family as the che-mcps servers
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk.git",
            .upToNextMinor(from: "0.12.0")),
    ],
    targets: [
        .target(
            name: "BestASRKit",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            resources: [.copy("Supply/weights-manifest.json")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "bestasr",
            dependencies: [
                "BestASRKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "BestASRMCPCore",
            dependencies: [
                "BestASRKit",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "bestasr-mcp",
            dependencies: ["BestASRMCPCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BestASRKitTests",
            dependencies: [
                "BestASRKit",
                "BestASRMCPCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
