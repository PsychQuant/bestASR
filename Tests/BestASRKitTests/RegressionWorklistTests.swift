import Foundation
import Testing

@testable import BestASRKit

/// Baseline field-validation contracts (#116 extraction, #115 model whitelist).
///
/// `scripts/lib/baseline-worklist.py` is the single implementation of the
/// gate's baseline-field validation; these tests exercise the REAL script via
/// Process (same discipline as `RegressionBaselineTests` does for
/// `baseline-compare.py`) rather than re-implementing the rules in Swift where
/// they could drift from what `scripts/regression-gate.sh` actually runs.
///
/// The load-bearing contract here is CROSS-MODE: both `--emit worklist` and
/// `--emit model` run the COMPLETE validation pass. Validating only the fields
/// a given mode emits is exactly the two-heredoc divergence that let `model`
/// reach a path sink (`MODEL_DIR` → `cd`) and a CLI arg (`--models`) unchecked
/// for the whole of #112's lifetime.
struct RegressionWorklistTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    static let script = repoRoot.appendingPathComponent("scripts/lib/baseline-worklist.py")

    /// Runs the real lib against a baseline file, keeping stdout and stderr
    /// separate — a negative test must be able to assert that a rejected value
    /// never reached stdout (where the gate would consume it).
    private func run(emit: String, baselinePath: String) async throws -> (
        exit: Int32, stdout: String, stderr: String
    ) {
        // #165 family-wide sweep: this used to drain stdout to EOF and only
        // then read stderr — the exact sequential-drain deadlock #158 named. A
        // python3 run that filled stderr first would block in write(2), never
        // close stdout, and wedge the test forever. Routed through the shared
        // runner so the correct shape is the only shape (#165 verify B4/B5).
        try await SubprocessRunner.run(
            executable: "/usr/bin/python3",
            arguments: [Self.script.path, "--emit", emit, baselinePath],
            timeout: 120, backend: "regression-worklist-test")
    }

    /// Same, for a synthetic baseline written to a temp file.
    private func run(emit: String, baseline: Any) async throws -> (
        exit: Int32, stdout: String, stderr: String
    ) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bestasr-worklist-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: baseline).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await run(emit: emit, baselinePath: url.path)
    }

    private func entry(
        corpus: String = "c1", language: String = "zh", model: String = "large-v3-turbo"
    ) -> [String: Any] {
        [
            "corpus": corpus, "language": language, "model": model,
            "metric": "cer", "golden": 0.10, "tolerance": 0.02,
        ]
    }

    // MARK: - regression lock: extraction must not change a single byte (#116)

    /// The pre-extraction inline heredoc (regression-gate.sh L40-63) emitted
    /// exactly these bytes for benchmarks/baseline.json — captured before the
    /// refactor, sha256 e3f18b26660a8132b738d2ffd62c80427d18fa2f7b6eb18194243182ee646d85.
    static let pinnedWorklist = """
        jfk\ten
        osr-harvard-1\ten
        osr-harvard-2\ten
        osr-harvard-3\ten
        fleurs-ja-1\tja
        fleurs-ja-2\tja
        fleurs-ja-3\tja
        fleurs-ja-4\tja
        cv-zhtw-1\tzh
        cv-zhtw-2\tzh
        cv-zhtw-3\tzh
        cv-zhtw-4\tzh

        """

    @Test func `worklist emit on the real baseline is byte-identical to pre-extraction`() async throws {
        let baseline = Self.repoRoot.appendingPathComponent("benchmarks/baseline.json")
        let r = try await run(emit: "worklist", baselinePath: baseline.path)
        #expect(r.exit == 0)
        #expect(r.stdout == Self.pinnedWorklist)
        #expect(r.stdout.split(separator: "\n", omittingEmptySubsequences: false).count == 13)
        for line in r.stdout.split(separator: "\n") {
            #expect(line.split(separator: "\t").count == 2, "not corpus\\tlanguage: \(line)")
        }
    }

    @Test func `model emit on the real baseline is the reference model`() async throws {
        let baseline = Self.repoRoot.appendingPathComponent("benchmarks/baseline.json")
        let r = try await run(emit: "model", baselinePath: baseline.path)
        #expect(r.exit == 0)
        #expect(r.stdout == "large-v3-turbo\n")
    }

    // MARK: - model whitelist (#115)

    /// The empirically reproduced payload: `model` reaches MODEL_DIR (a `cd`
    /// target) and `--models` (a CLI arg), so a traversal segment must never
    /// leave the validator.
    @Test func `a traversal model is rejected and never reaches stdout`() async throws {
        let payload = "large-v3-turbo/../../../../../../etc"
        let r = try await run(emit: "model", baseline: [entry(model: payload)])
        #expect(r.exit != 0)
        #expect(r.stdout.isEmpty, "forged model leaked to stdout: \(r.stdout)")
        #expect(r.stderr.contains("unsafe model in baseline"))
    }

    @Test func `path-shaped and metacharacter models are rejected`() async throws {
        let hostile = [
            "/etc/passwd",  // absolute path
            "..",  // bare traversal
            "../large-v3-turbo",  // leading traversal
            "a/../b",  // internal traversal
            "large-v3-turbo\nlarge-v2",  // newline (record forgery)
            "large-v3-turbo\tx",  // tab
            "large-v3-turbo; rm -rf /",  // shell metacharacters
            "large-v3-turbo$(whoami)",  // command substitution
            "large-v3-turbo|cat",  // pipe
            "large-v3-turbo&",  // background
            "owner/repo/extra",  // more than one path segment
            "owner/repo",  // ANY slash — model is a single path component (#126 verify)
            ".hidden",  // leading dot
            "",  // empty
            // These two pass the charset+start rules and are caught ONLY by the
            // `".." in model` substring guard. Every other hostile entry above
            // fails on some other rule, so without these the guard is unlocked —
            // deleting that line would leave the suite green (#126 verify, Codex).
            "a..b",
            "large-v3..turbo",
        ]
        for model in hostile {
            let r = try await run(emit: "model", baseline: [entry(model: model)])
            #expect(r.exit != 0, "accepted hostile model: \(model.debugDescription)")
            #expect(r.stdout.isEmpty, "leaked to stdout: \(model.debugDescription)")
            // Assert the specific rejection, not merely a non-zero exit — a
            // crash or a missing script would otherwise pass this vacuously.
            #expect(
                r.stderr.contains("unsafe model in baseline"),
                "wrong failure for \(model.debugDescription): \(r.stderr)")
        }
    }

    @Test func `legitimate model names are accepted`() async throws {
        // Single path components only. `owner/repo` is deliberately NOT here:
        // that shape lives in ModelGrid's `hfRepo`, not the baseline `model`
        // field, and neither sink accepts a slash (#126 verify).
        for model in ["large-v3-turbo", "distil-whisper_v3.5", "tiny.en"] {
            let r = try await run(emit: "model", baseline: [entry(model: model)])
            #expect(r.exit == 0, "rejected legitimate model: \(model) — \(r.stderr)")
            #expect(r.stdout == model + "\n")
        }
    }

    // MARK: - corpus / language locks carried over from the heredoc

    @Test func `an unsafe corpus name still fails loud`() async throws {
        let r = try await run(emit: "worklist", baseline: [entry(corpus: "../../etc/passwd")])
        #expect(r.exit != 0)
        #expect(r.stdout.isEmpty)
        #expect(r.stderr.contains("unsafe corpus name in baseline"))
    }

    @Test func `a duplicate corpus still fails loud`() async throws {
        let r = try await run(emit: "worklist", baseline: [entry(), entry()])
        #expect(r.exit != 0)
        #expect(r.stderr.contains("duplicate corpus in baseline"))
    }

    /// #112 regression lock: an embedded newline in `language` forges a second
    /// worklist record whose corpus never passed the charset check.
    @Test func `a newline-injecting language still fails loud`() async throws {
        let r = try await run(
            emit: "worklist", baseline: [entry(language: "zh\n../../etc/passwd\ten")])
        #expect(r.exit != 0)
        #expect(r.stdout.isEmpty, "forged record leaked to stdout: \(r.stdout)")
        #expect(r.stderr.contains("unsafe language in baseline"))
    }

    @Test func `an empty baseline fails loud`() async throws {
        let r = try await run(emit: "worklist", baseline: [])
        #expect(r.exit != 0)
        #expect(r.stderr.contains("baseline is empty"))
        let m = try await run(emit: "model", baseline: [])
        #expect(m.exit != 0)
        #expect(m.stderr.contains("baseline is empty"))
    }

    // MARK: - THE contract: both modes run the COMPLETE validation pass

    /// This is the reason #116 and #115 ship together. Under the old two-heredoc
    /// layout the model stage read entries[0]["model"] with no validation at
    /// all — each stage only looked at the fields it emitted. Emitting the model
    /// must therefore still fail on a bad language or a bad corpus, and emitting
    /// the worklist must still fail on a bad model.
    @Test func `model emit fails on a bad language`() async throws {
        let r = try await run(emit: "model", baseline: [entry(language: "zh\nforged\ten")])
        #expect(r.exit != 0, "model mode skipped language validation — divergence is back")
        #expect(r.stdout.isEmpty)
        #expect(r.stderr.contains("unsafe language in baseline"))
    }

    @Test func `model emit fails on a bad corpus`() async throws {
        let r = try await run(emit: "model", baseline: [entry(corpus: "a b; rm -rf /")])
        #expect(r.exit != 0, "model mode skipped corpus validation — divergence is back")
        #expect(r.stdout.isEmpty)
        #expect(r.stderr.contains("unsafe corpus name in baseline"))
    }

    @Test func `worklist emit fails on a bad model`() async throws {
        let r = try await run(
            emit: "worklist", baseline: [entry(model: "large-v3-turbo/../../../etc")])
        #expect(r.exit != 0, "worklist mode skipped model validation — divergence is back")
        #expect(r.stdout.isEmpty)
        #expect(r.stderr.contains("unsafe model in baseline"))
    }

    /// The validation pass covers every entry, not just entries[0] (the one the
    /// gate happens to read the reference model from today).
    @Test func `a bad field in a later entry fails both modes`() async throws {
        let baseline: [Any] = [entry(corpus: "c1"), entry(corpus: "c2", model: "../escape")]
        for mode in ["worklist", "model"] {
            let r = try await run(emit: mode, baseline: baseline)
            #expect(r.exit != 0, "\(mode) mode validated only the first entry")
            #expect(r.stdout.isEmpty)
            #expect(r.stderr.contains("unsafe model in baseline"))
        }
    }
}
