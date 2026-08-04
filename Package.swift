// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bestasr",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "bestasr", targets: ["bestasr"]),
        .executable(name: "bestasr-mcp", targets: ["bestasr-mcp"]),
        .executable(name: "bestasr-gui", targets: ["bestasr-gui"]),
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
        // #87 GUI dual-track: logic in a library target (mirrors BestASRMCPCore)
        // so the session state machine is testable without SwiftUI.
        .target(
            name: "BestASRGUICore",
            dependencies: ["BestASRKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "bestasr-gui",
            dependencies: ["BestASRGUICore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Test fixture, deliberately NOT in `products`, so nothing ships it:
        // `release-app.sh` and `release-mcp.sh` build per-product and
        // `install.sh` copies two named binaries. (`swift run
        // bestasr-diagnostics-probe` *does* work — `swift run` takes target
        // names, not just product names — but that is a developer convenience,
        // not a distribution path.) `swift test` builds it so
        // `TranscribeDiagnosticsDefaultStreamTests` can spawn it. It exists to
        // execute `TranscribeDiagnostics.report`'s stream defaults in a real
        // process — see its source for why the real CLI cannot stand in (#136).
        .executableTarget(
            name: "bestasr-diagnostics-probe",
            dependencies: ["BestASRKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BestASRKitTests",
            dependencies: [
                "BestASRKit",
                "BestASRMCPCore",
                "BestASRGUICore",
                // CLI parse regression tests (#101: ArgumentParser negative-value
                // form) — SwiftPM links executable targets into tests since 5.5.
                "bestasr",
                // Depended on so `swift test` builds it into the products
                // directory, where the test spawns it as a subprocess. SwiftPM
                // also links its objects into the test bundle (`nm` finds
                // `_bestasr_diagnostics_probe_main` there); no test references
                // any of its symbols, but the dependency is not symbol-free.
                "bestasr-diagnostics-probe",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
