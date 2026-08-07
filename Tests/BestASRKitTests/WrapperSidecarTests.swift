import Foundation
import Testing

@testable import BestASRKit

/// Regression lock for the wrapper's self-heal decision (#163 verify B1).
///
/// Defect 3 in #163 was not "the sidecar will lie in future" — it was the field
/// state the issue *measured*: sidecar `0.16.0`, plugin.json `0.16.0`, binary
/// actually `0.15.0` and crashing. The first fix corrected only the write path,
/// so a machine already in that state short-circuited before any resolution and
/// would have kept the broken binary forever — including after a fixed release.
/// Four review lenses caught it independently, and it shipped with no test.
///
/// These tests drive the real wrapper against a sandboxed install dir with no
/// network, and assert on the *decision* it announces on stderr.
struct WrapperSidecarTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var wrapper: URL {
        repoRoot.appendingPathComponent("plugins/bestasr/bin/bestasr-mcp-wrapper.sh")
    }

    /// Runs the wrapper with a sandboxed install dir and no network reachable,
    /// returning its stderr. `PATH` keeps the real tools but `curl` is stubbed
    /// to fail, so resolution cannot succeed and the run stops after announcing
    /// its decision.
    private func runWrapper(sidecar: String?, binaryPresent: Bool) async throws -> String {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrapper-\(UUID().uuidString)", isDirectory: true)
        let bin = sandbox.appendingPathComponent("bin", isDirectory: true)
        let stubs = sandbox.appendingPathComponent("stubs", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stubs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        if binaryPresent {
            let fake = bin.appendingPathComponent("bestasr-mcp")
            try "#!/bin/sh\nexit 0\n".write(to: fake, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: fake.path)
        }
        if let sidecar {
            try sidecar.write(
                to: bin.appendingPathComponent(".bestasr-mcp.version"),
                atomically: true, encoding: .utf8)
        }
        // curl always fails → no resolution can complete, so the wrapper's
        // announced reason is the whole observable behaviour.
        let curlStub = stubs.appendingPathComponent("curl")
        try "#!/bin/sh\nexit 7\n".write(to: curlStub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: curlStub.path)

        var env = ProcessInfo.processInfo.environment
        env["BESTASR_WRAPPER_INSTALL_DIR"] = bin.path
        env["PATH"] = stubs.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")

        // NOTE: this spawns directly because `SubprocessRunner` lives on the
        // #165 branch, which is independent of this one and must merge first
        // (#165 → #163 → #164, per the diagnosis ordering). Once #165 lands,
        // its SpawnSiteSweepTests guard will flag this site and force the
        // conversion — which is the guard doing its job, not a surprise.
        // Meanwhile the drains run concurrently, because "the output is small"
        // is precisely the reasoning that left #158 open.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.wrapper.path]
        process.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()

        final class DataBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value = Data()
            func set(_ d: Data) { lock.withLock { value = d } }
            var get: Data { lock.withLock { value } }
        }
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()
        for (pipe, box) in [(outPipe, outBox), (errPipe, errBox)] {
            group.enter()
            DispatchQueue.global().async {
                box.set(pipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
        }
        group.wait()
        process.waitUntilExit()
        return String(decoding: errBox.get, as: UTF8.self)
    }

    /// The exact poisoned state the issue tabulated. Plugin.json pins 0.16.0;
    /// a pre-fix wrapper wrote a bare `0.16.0` while installing 0.15.0. The
    /// wrapper must distrust that value and re-resolve — if it short-circuits,
    /// no future release can ever reach this machine.
    @Test func `A pre-fix sidecar is distrusted so the machine can still be healed`()
        async throws
    {
        let stderr = try await runWrapper(sidecar: "0.16.0", binaryPresent: true)
        #expect(
            stderr.contains("sidecar predates"),
            "a legacy sidecar must force one resolution; got: \(stderr)")
    }

    /// A schema-tagged sidecar matching the pin is trustworthy: no re-resolution,
    /// no needless download on every MCP spawn.
    @Test func `A current schema-tagged sidecar matching the pin resolves nothing`()
        async throws
    {
        let pinned = try pluginVersion()
        let stderr = try await runWrapper(sidecar: "v2:\(pinned)", binaryPresent: true)
        #expect(
            !stderr.contains("sidecar predates"),
            "a v2 sidecar must not be treated as legacy; got: \(stderr)")
        #expect(
            !stderr.contains("checking"),
            "a matching v2 sidecar must not trigger resolution; got: \(stderr)")
    }

    /// No sidecar at all is a first install, not a legacy one — the message must
    /// not blame a sidecar that never existed.
    @Test func `A missing sidecar reads as a first install`() async throws {
        let stderr = try await runWrapper(sidecar: nil, binaryPresent: false)
        #expect(stderr.contains("binary not installed"), "got: \(stderr)")
        #expect(!stderr.contains("sidecar predates"), "got: \(stderr)")
    }

    private func pluginVersion() throws -> String {
        let json = Self.repoRoot.appendingPathComponent(
            "plugins/bestasr/.claude-plugin/plugin.json")
        let data = try Data(contentsOf: json)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["version"] as? String) ?? ""
    }
}
