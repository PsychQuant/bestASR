import CryptoKit
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
@Suite(.serialized)
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
        return try runScript(Self.wrapper.path, env: env)
    }

    /// Runs a shell script and returns its stderr.
    ///
    /// Spawns directly because `SubprocessRunner` lives on the #165 branch,
    /// which is independent of this one and merges first (#165 → #163 → #164).
    /// Once #165 lands, its SpawnSiteSweepTests guard will flag this site and
    /// force the conversion — that is the guard working. Both pipes are drained
    /// concurrently and the wait is bounded, because "the output is small" is
    /// exactly the reasoning that left #158 open.
    @discardableResult
    private func runScript(_ path: String, env: [String: String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [path]
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
        // Scaled to the machine. 60s is generous on an 18-core dev box and
        // tight on a 3-core CI runner where a dozen suites spawn processes at
        // once — CI failed here with "exceeded its 60s budget" while every
        // other test in the run also reported ~64s, i.e. the whole process was
        // contended, not the wrapper. The budget's job is that a hung wrapper
        // fails instead of stalling forever, and it still does that.
        let budgetSeconds = ProcessInfo.processInfo.activeProcessorCount >= 8 ? 60 : 180
        if group.wait(timeout: .now() + .seconds(budgetSeconds)) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + .seconds(2))
            throw BestASRError.runtime("wrapper test exceeded its \(budgetSeconds)s budget")
        }
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

    /// Round-2 H2/M1: every existing wrapper test stubs `curl` to fail, so the
    /// download-and-verify branch — where the sidecar is actually upgraded and
    /// where B3's whole verification lives — had no coverage at all. "B1 is
    /// closed" rested on the machine being *marked* for re-resolution, which is
    /// a different claim from re-resolution actually healing it once.
    ///
    /// This drives the real wrapper through a successful install with a stubbed
    /// registry, and asserts the end state: a schema-tagged sidecar carrying the
    /// tag that was RECEIVED.
    @Test func `A successful download upgrades the sidecar to the received tag`()
        async throws
    {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrapper-ok-\(UUID().uuidString)", isDirectory: true)
        let bin = sandbox.appendingPathComponent("bin", isDirectory: true)
        let stubs = sandbox.appendingPathComponent("stubs", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stubs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // A poisoned legacy sidecar: the exact state #163 measured.
        try "0.16.0".write(
            to: bin.appendingPathComponent(".bestasr-mcp.version"),
            atomically: true, encoding: .utf8)

        // Registry stub. Serves a release whose tag (v0.15.9) deliberately
        // differs from the plugin's pin, so the assertion distinguishes
        // "recorded what we received" from "recorded what we asked for".
        let payload = "#!/bin/sh\nexit 0\n"
        let payloadFile = sandbox.appendingPathComponent("payload")
        try payload.write(to: payloadFile, atomically: true, encoding: .utf8)
        let digest = try shasum(of: payloadFile)

        let curl = stubs.appendingPathComponent("curl")
        try """
            #!/bin/sh
            for a in "$@"; do
              case "$a" in
                *releases/tags/*|*releases/latest*)
                  printf '%s' '{"tag_name":"v0.15.9","assets":[{"browser_download_url":"https://x/bestasr-mcp"},{"browser_download_url":"https://x/bestasr-mcp.sha256"}]}'
                  exit 0 ;;
                *bestasr-mcp.sha256) printf '%s  bestasr-mcp\n' '\(digest)'; exit 0 ;;
              esac
            done
            # binary fetch: -o <dest> is the last pair
            dest=""
            prev=""
            for a in "$@"; do
              [ "$prev" = "-o" ] && dest="$a"
              prev="$a"
            done
            [ -n "$dest" ] && cp '\(payloadFile.path)' "$dest"
            exit 0
            """.write(to: curl, atomically: true, encoding: .utf8)

        // codesign stub: the identity check is exercised for real elsewhere
        // (the requirement string is validated against a genuine release,
        // an ad-hoc binary and a self-signed one); here it stands in so the
        // test does not depend on a Developer ID cert being present.
        let codesign = stubs.appendingPathComponent("codesign")
        try "#!/bin/sh\nexit 0\n".write(to: codesign, atomically: true, encoding: .utf8)

        for tool in [curl, codesign] {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: tool.path)
        }

        var env = ProcessInfo.processInfo.environment
        env["BESTASR_WRAPPER_INSTALL_DIR"] = bin.path
        env["PATH"] = stubs.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        _ = try runScript(Self.wrapper.path, env: env)

        let sidecar = try String(
            contentsOf: bin.appendingPathComponent(".bestasr-mcp.version"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(
            sidecar == "v2:0.15.9",
            "sidecar must be schema-tagged and carry the RECEIVED tag; got: \(sidecar)")
        #expect(
            FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("bestasr-mcp").path),
            "the verified binary should have been installed")
    }

    private func shasum(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var hasher = SHA256()
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func pluginVersion() throws -> String {
        let json = Self.repoRoot.appendingPathComponent(
            "plugins/bestasr/.claude-plugin/plugin.json")
        let data = try Data(contentsOf: json)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["version"] as? String) ?? ""
    }
}

/// #163 round 4. Two CRITICALs and several HIGHs all lived on one path that no
/// test reached: a download that completes and then FAILS verification while an
/// existing binary is present. The round-3 security fix turned an `exec` there
/// into a fall-through, and the fall-through ran into the install sequence — so
/// a rejected binary stamped the sidecar with its version and announced
/// "installed". The binary on disk was never replaced, but the bookkeeping lie
/// was enough: the next spawn matched the poisoned sidecar, skipped resolution,
/// and ran the stale binary forever. That is the self-heal defeat #163 exists
/// to fix, reintroduced by its own fix.
///
/// These drive the real wrapper with a stubbed registry that serves an unsigned
/// payload, so `codesign` runs for real and genuinely rejects it.
@Suite(.serialized)
struct WrapperVerificationRejectionTests {
    private struct Sandbox {
        let bin: URL
        let root: URL
        var sidecarPath: URL { bin.appendingPathComponent(".bestasr-mcp.version") }
        var binaryPath: URL { bin.appendingPathComponent("bestasr-mcp") }
        var sidecar: String? { try? String(contentsOf: sidecarPath, encoding: .utf8) }
        var binaryBody: String? { try? String(contentsOf: binaryPath, encoding: .utf8) }
    }

    /// Serves release metadata for `servedTag` and an unsigned file as the
    /// binary asset, so verification fails on genuine grounds.
    private func makeSandbox(sidecar: String?, servedTag: String) throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrapper-reject-\(UUID().uuidString)", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let stubs = root.appendingPathComponent("stubs", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stubs, withIntermediateDirectories: true)

        let existing = bin.appendingPathComponent("bestasr-mcp")
        try "#!/bin/sh\necho EXISTING\n".write(to: existing, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: existing.path)
        if let sidecar {
            try sidecar.write(
                to: bin.appendingPathComponent(".bestasr-mcp.version"),
                atomically: true, encoding: .utf8)
        }

        let curl = stubs.appendingPathComponent("curl")
        try """
            #!/bin/sh
            for a in "$@"; do
              case "$a" in
                *api.github.com*)
                  printf '{"tag_name":"v\(servedTag)","assets":[{"browser_download_url":"https://example.invalid/bestasr-mcp"}]}'
                  exit 0;;
              esac
            done
            prev=""
            for a in "$@"; do
              [ "$prev" = "-o" ] && { printf 'definitely not a signed mach-o\\n' > "$a"; exit 0; }
              prev="$a"
            done
            exit 0
            """.write(to: curl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: curl.path)

        var env = ProcessInfo.processInfo.environment
        env["BESTASR_WRAPPER_INSTALL_DIR"] = bin.path
        env["PATH"] = stubs.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        let wrapper = WrapperSidecarTests.wrapper.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [wrapper]
        p.environment = env
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        return Sandbox(bin: bin, root: root)
    }

    @Test func `A rejected download must not stamp the sidecar with its version`() throws {
        let box = try makeSandbox(sidecar: "v2:0.15.0\n", servedTag: "0.16.0")
        defer { try? FileManager.default.removeItem(at: box.root) }

        let after = (box.sidecar ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(
            after == "v2:0.15.0",
            "the sidecar was moved to the REJECTED version — the next spawn will believe this machine is current and never re-resolve; got '\(after)'")
        // And the binary itself must be untouched.
        #expect(box.binaryBody?.contains("EXISTING") == true)
    }

    @Test func `A rejected download leaves the machine able to re-resolve`() throws {
        // No sidecar at all: the wrapper must not invent one for a binary it
        // refused to install.
        let box = try makeSandbox(sidecar: nil, servedTag: "0.16.0")
        defer { try? FileManager.default.removeItem(at: box.root) }
        #expect(
            box.sidecar == nil,
            "a refused install wrote a sidecar, which suppresses the next re-resolution")
    }
}
