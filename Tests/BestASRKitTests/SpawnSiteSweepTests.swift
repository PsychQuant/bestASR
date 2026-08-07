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
        // The justification must name what this entry RETAINS, not only what it
        // solved. The first version said only "fixed in place with a concurrent
        // drain" — true, but it described the risk that went away while staying
        // silent about the one left behind, and it cited #170 (descendant kill)
        // for a stdin gap #170 is not about. Round-2 review rated the same site
        // LOW / MEDIUM / HIGH across three reviewers, and that spread was itself
        // evidence the text was unclear.
        "Tests/BestASRKitTests/RegressionBaselineTests.swift":
            "Feeds the child on stdin, which SubprocessRunner does not support "
            + "(stdin support is tracked in #170's Expected list, item 4 — NOT "
            + "the descendant-kill gap #170 is named for). The #158-shaped "
            + "ordering deadlock IS fixed in place with a concurrent drain. "
            + "RETAINED RISK: the site now carries its own bounded wait, so it "
            + "fails rather than stalls, but it is still the one spawn in the "
            + "tree not covered by the shared deadline. Remove this entry once "
            + "#170 adds stdin support.",
    ]

    /// Does this source text construct a subprocess directly?
    ///
    /// The first version matched the literal `Process()`. Round-2 review proved
    /// that four ordinary spellings slip past it — `Process ()`, `.init()` on a
    /// `Process`-typed binding, a construction split across lines, and a
    /// `typealias` — each confirmed to build a real `NSConcreteTask`. `.init()`
    /// is the dangerous one: it is idiomatic Swift where the type is already
    /// known, so it needs no intent to evade.
    ///
    /// This is still a *lint*, not a proof. It cannot see a spawn behind
    /// `posix_spawn`, `fork/exec`, or a helper in another module. What it does
    /// is raise the cost of reintroducing the pattern by accident, which is how
    /// #91 → #158 → #165 actually happened — nobody was evading a check, there
    /// simply wasn't one. `spawnDetectionIsNotVacuous` below keeps it honest.
    static func spawnsDirectly(_ text: String) -> Bool {
        // Strip comments first. Prose about spawning is not spawning — the
        // widened patterns below match ordinary English like "…through Process
        // (same discipline as…", and the previous self-exclusion special case
        // was papering over this same root cause rather than fixing it.
        let code = text
            .replacingOccurrences(
                of: #"/\*[\s\S]*?\*/"#, with: " ", options: .regularExpression)
            .replacingOccurrences(
                of: #"(?m)//.*$"#, with: " ", options: .regularExpression)

        let patterns = [
            #"\bProcess\s*\("#,  // Process(), Process (), split across lines
            #"\bProcess\s*\.\s*init\s*\("#,  // Process.init()
            #":\s*Process\s*=\s*\.\s*init\s*\("#,  // let p: Process = .init()
            #"\bNSTask\s*\("#,  // the ObjC spelling
            #"\bposix_spawn(p)?\s*\("#,  // below Foundation entirely
        ]
        for pattern in patterns
        where code.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        // A `typealias X = Process` makes any `X(` a spawn. Catch the alias
        // itself rather than trying to track every use of it.
        if code.range(of: #"typealias\s+\w+\s*=\s*Process\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

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
                // The vacuity test below embeds real spawn spellings as string
                // literals; comment-stripping does not remove those. The scanner
                // spawns nothing itself.
                if relative == Self.scannerPath { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                guard Self.spawnsDirectly(text) else { continue }
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

    /// A guard that cannot fail is worse than no guard, because it is believed.
    /// These are the exact spellings round-2 review used to walk past the first
    /// version of this check — each was confirmed to construct a real process.
    @Test func `Spawn detection is not vacuous`() {
        let mustDetect = [
            "let p = Process()",
            "let p = Process ()",  // extra space
            "let p: Process = .init()",  // idiomatic where the type is known
            "let p = Process(\n)",  // split across lines
            "typealias Proc = Process\nlet p = Proc()",  // aliased
            "let t = NSTask()",  // ObjC spelling
            "posix_spawn(&pid, path, nil, nil, argv, envp)",  // below Foundation
        ]
        for sample in mustDetect {
            #expect(
                Self.spawnsDirectly(sample),
                "spawn detection missed: \(sample.replacingOccurrences(of: "\n", with: "⏎"))")
        }

        let mustNotDetect = [
            "// we deliberately avoid Process here",
            "let info = ProcessInfo.processInfo",  // not a spawn
            "func processAll() {}",  // substring of an unrelated identifier
        ]
        for sample in mustNotDetect {
            #expect(!Self.spawnsDirectly(sample), "false positive on: \(sample)")
        }
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
