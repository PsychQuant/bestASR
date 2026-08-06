import Foundation
import Testing

/// Contract for `scripts/check-probe-markers.sh`, exercised as the real script
/// via `Process` rather than reimplemented here.
///
/// The script answers three different questions and must not conflate them:
/// every marker is present (0), a marker is missing (1), or the request was
/// unusable so nothing was checked (2). Earlier versions of this check lived as
/// a snippet embedded in an evidence file and reported the third case as the
/// first — under `set -u` with an unset array, and again when pasted into an
/// interactive shell, where a `${var:?}` guard only warns.
///
/// The marker rules are not style. Each one, violated, produces a wrong answer
/// rather than an error: `strings` will not emit a run shorter than four
/// characters, it splits a run at any byte ≥ 0x80, `grep -F` with an empty
/// pattern matches anything, and `grep -F` is a substring test, so a marker
/// contained in another marker is answered by the wrong one.
struct ProbeMarkerCheckTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    static let script = repoRoot.appendingPathComponent("scripts/check-probe-markers.sh")

    enum Status: Int32 { case allPresent = 0, missing = 1, unusable = 2 }

    /// A file whose `strings` output contains the given literals.
    private static func fixture(containing literals: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-marker-fixture-\(UUID().uuidString)")
        // NUL-separated so each literal is its own printable run, as a probe
        // marker compiled into a binary would be.
        let body = literals.map { $0 + "\0" }.joined()
        try Data(body.utf8).write(to: url)
        return url
    }

    @discardableResult
    private static func run(_ arguments: [String], tmpdir: URL? = nil) throws -> (
        status: Int32, output: String
    ) {
        let process = Process()
        process.executableURL = script
        process.arguments = arguments
        if let tmpdir {
            var env = ProcessInfo.processInfo.environment
            env["TMPDIR"] = tmpdir.path
            process.environment = env
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: - The three answers

    @Test func `it separates present, missing, and could-not-check`() throws {
        let file = try Self.fixture(containing: ["PROBE_ALPHA", "PROBE_BETA"])
        defer { try? FileManager.default.removeItem(at: file) }

        let present = try Self.run([file.path, "PROBE_ALPHA", "PROBE_BETA"])
        #expect(present.status == Status.allPresent.rawValue, "\(present.output)")

        let missing = try Self.run([file.path, "PROBE_ALPHA", "PROBE_GAMMA"])
        #expect(missing.status == Status.missing.rawValue, "\(missing.output)")
        #expect(missing.output.contains("PROBE_GAMMA"), "the missing marker should be named")
        #expect(!missing.output.contains("PROBE_ALPHA"), "a present marker should not be reported")

        let unusable = try Self.run([file.path])
        #expect(unusable.status == Status.unusable.rawValue, "\(unusable.output)")
    }

    /// The failure this whole check exists for: a build that never took the
    /// patch yields a binary with none of the markers.
    @Test func `a binary with no markers at all is reported missing, not unusable`() throws {
        let file = try Self.fixture(containing: ["something else entirely"])
        defer { try? FileManager.default.removeItem(at: file) }

        let result = try Self.run([file.path, "PROBE_ALPHA"])
        #expect(result.status == Status.missing.rawValue, "\(result.output)")
    }

    // MARK: - The marker contract

    @Test func `it refuses a marker request that could not give a true answer`() throws {
        let file = try Self.fixture(containing: ["PROBE_ALPHA", "PROBE_ALPHA_LONGER"])
        defer { try? FileManager.default.removeItem(at: file) }

        let cases: [(name: String, markers: [String], because: String)] = [
            ("no markers", [], "nothing would be checked"),
            ("empty marker", [""], "grep -F with an empty pattern matches anything"),
            ("shorter than four characters", ["abc"], "strings does not emit runs that short"),
            ("non-ASCII", ["PROBE\u{2192}ARROW"], "strings splits the run at any byte >= 0x80"),
            ("one marker inside another", ["PROBE_ALPHA", "PROBE_ALPHA_LONGER"],
             "the shorter is found whenever the longer is present"),
        ]

        for c in cases {
            let result = try Self.run([file.path] + c.markers)
            #expect(
                result.status == Status.unusable.rawValue,
                """
                \(c.name): expected status 2 (nothing checked) because \(c.because), \
                got \(result.status). Output: \(result.output)
                """)
        }
    }

    @Test func `it refuses a binary it cannot read`() throws {
        for path in ["/no/such/binary", Self.repoRoot.appendingPathComponent("scripts").path] {
            let result = try Self.run([path, "PROBE_ALPHA"])
            #expect(result.status == Status.unusable.rawValue, "\(path): \(result.output)")
        }
    }

    // MARK: - It leaves nothing behind

    /// The snippet this replaced created a temporary file and abandoned it on
    /// one of its failure paths.
    ///
    /// Measured in a private `TMPDIR`, not the shared per-user directory: every
    /// process on the machine writes there, so counting it would measure their
    /// activity as well as the script's and give an answer that is right or
    /// wrong by coincidence.
    @Test func `it removes its temporary file on every path`() throws {
        let file = try Self.fixture(containing: ["PROBE_ALPHA"])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-marker-tmp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: tempDir)
        }

        func leftBehind() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        }

        for (label, arguments) in [
            ("all present", [file.path, "PROBE_ALPHA"]),
            ("a marker missing", [file.path, "PROBE_MISSING_HERE"]),
            ("marker rejected", [file.path, "ab"]),
            ("binary rejected", ["/no/such/binary", "PROBE_ALPHA"]),
        ] {
            try Self.run(arguments, tmpdir: tempDir)
            let leaked = try leftBehind()
            #expect(leaked.isEmpty, "\(label): left \(leaked) behind in TMPDIR")
        }
    }
}
