import Foundation
import Testing

/// The mechanical replacement for a human "family-wide sweep" (#165 verify B4).
///
/// Why this test exists rather than another round of grepping: the same
/// pipe-deadlock shape has now shipped three times — #91 (external adapter),
/// #158 (test helpers), #165 (`WhisperCppEngine`) — and each fix stayed local to
/// the file that happened to hurt. The #165 fix itself then *claimed* a
/// family-wide sweep while having only searched `Sources/`, leaving three more
/// sites in `Tests/`, one of them strictly worse than the original bug.
///
/// A sweep that depends on someone remembering to sweep is the recurrence
/// mechanism. So: every `Process()` in the tree must either go through
/// `SubprocessRunner` or be listed here with a reason. A new spawn site fails
/// this test until its author makes that choice explicitly.
struct SpawnSiteSweepTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    /// This file, relative to the repo root — derived rather than hardcoded so a
    /// rename cannot silently turn the self-exclusion into a blind spot.
    static let scannerPath = URL(fileURLWithPath: #filePath).path
        .replacingOccurrences(of: repoRoot.path + "/", with: "")

    /// Paths permitted to construct `Process` directly, each with the reason.
    /// Adding an entry is a deliberate act; it should be rare and justified.
    static let allowed: [String: String] = [
        "Sources/BestASRKit/Engines/SubprocessRunner.swift":
            "the shared runner itself — this is the one correct implementation",
        "Tests/BestASRKitTests/RegressionBaselineTests.swift":
            "feeds the child on stdin; SubprocessRunner has no stdin support (#170). "
            + "Fixed in place with a concurrent drain and documented at the call site.",
    ]

    private func swiftFiles(under directory: String) -> [URL] {
        let root = Self.repoRoot.appendingPathComponent(directory)
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test func `Every direct Process() spawn is either the shared runner or an allowlisted exception`()
        throws
    {
        var offenders: [String] = []
        for directory in ["Sources", "Tests"] {
            for file in swiftFiles(under: directory) {
                let relative = file.path.replacingOccurrences(
                    of: Self.repoRoot.path + "/", with: "")
                // The scanner names the pattern in its own docs and failure
                // message, so it matches itself. It spawns nothing.
                if relative == Self.scannerPath { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                guard text.contains("Process()") else { continue }
                if Self.allowed[relative] == nil { offenders.append(relative) }
            }
        }

        #expect(
            offenders.isEmpty,
            """
            New direct Process() spawn site(s): \(offenders.sorted().joined(separator: ", ")).

            Route them through SubprocessRunner (concurrent drain + one deadline \
            covering the whole operation), or add the path to \
            SpawnSiteSweepTests.allowed with a reason. Do not hand-roll another \
            drain shape — three concurrent shapes for one concern is what #165 was about.
            """)
    }

    /// The allowlist must not outlive the files it names — a stale entry would
    /// silently re-permit a path that came back for a different reason.
    @Test func `Allowlist has no stale entries`() {
        for path in Self.allowed.keys {
            let url = Self.repoRoot.appendingPathComponent(path)
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "allowlisted path no longer exists, remove it: \(path)")
        }
    }
}
