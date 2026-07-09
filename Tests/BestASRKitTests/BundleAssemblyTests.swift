import Foundation
import Testing

@testable import BestASRKit

/// spec gui-app (#87): the release script's assemble-only mode produces the
/// dual-track bundle contract — three executables, correct Info.plist, version
/// pinned to BestASRVersion.current — with stub binaries and no credentials.
struct BundleAssemblyTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    @Test func `assemble-only builds the dual-track bundle contract`() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("bundle-assembly-\(UUID().uuidString)")
        let binDir = scratch.appendingPathComponent("bin")
        let outDir = scratch.appendingPathComponent("out")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        // Stub executables: the assemble stage only copies + sets exec bits.
        for name in ["bestasr-gui", "bestasr-mcp", "bestasr"] {
            let stub = binDir.appendingPathComponent(name)
            try "#!/bin/sh\nexit 0\n".write(to: stub, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.repoRoot.appendingPathComponent("scripts/release-app.sh").path,
            "--assemble-only",
        ]
        process.currentDirectoryURL = Self.repoRoot
        var env = ProcessInfo.processInfo.environment
        env["BIN_DIR"] = binDir.path
        env["OUT_DIR"] = outDir.path
        process.environment = env
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = stdout
        try process.run()
        process.waitUntilExit()
        let log = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, "script failed:\n\(log)")

        let app = outDir.appendingPathComponent("bestASR.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")

        // Exactly the three dual-track executables, each with the exec bit.
        // The CLI ships as bestasr-cli: on case-insensitive APFS a "bestasr"
        // entry IS "bestASR", so the naive name overwrites the GUI (spec gui-app).
        let contents = try fm.contentsOfDirectory(atPath: macOS.path).sorted()
        #expect(contents == ["bestASR", "bestasr-cli", "bestasr-mcp"])
        for name in contents {
            #expect(
                fm.isExecutableFile(atPath: macOS.appendingPathComponent(name).path),
                "\(name) lost its executable bit")
        }

        // Info.plist parses and carries the bundle contract.
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        let plist = try #require(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: plistURL), format: nil) as? [String: Any])
        #expect(plist["CFBundleIdentifier"] as? String == "com.psychquant.bestASR")
        #expect(plist["CFBundleExecutable"] as? String == "bestASR")
        #expect(plist["LSMinimumSystemVersion"] as? String == "14.0")
        // Version comes from the same constant the app reports — no drift.
        #expect(plist["CFBundleShortVersionString"] as? String == BestASRVersion.current)
        #expect(plist["CFBundleVersion"] as? String == BestASRVersion.current)
    }
}
