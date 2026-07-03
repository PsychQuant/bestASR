// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bestasr",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "bestasr", targets: ["bestasr"]),
        .library(name: "BestASRKit", targets: ["BestASRKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        // #25 diarization — exact pin per supply-chain discipline (design D3)
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.4"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "BestASRKit",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
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
        .testTarget(
            name: "BestASRKitTests",
            dependencies: [
                "BestASRKit",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
