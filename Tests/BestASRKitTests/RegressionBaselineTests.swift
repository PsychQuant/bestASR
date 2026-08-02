import Foundation
import Testing

@testable import BestASRKit

/// Regression-baseline contracts (spec regression-benchmark, #34): the pinned
/// baseline file's schema, and the gate's compare stage — exercised as the
/// REAL implementation (`scripts/lib/baseline-compare.py`) via Process, not a
/// Swift re-implementation that could drift from what the gate actually runs.
struct RegressionBaselineTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    // MARK: - baseline.json schema (spec: Machine-independent regression baseline)

    @Test func `baseline entries carry the full schema and accuracy only`() throws {
        let url = Self.repoRoot.appendingPathComponent("benchmarks/baseline.json")
        let data = try Data(contentsOf: url)
        let entries = try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(!entries.isEmpty)
        var names = Set<String>()
        for e in entries {
            let corpus = try #require(e["corpus"] as? String)
            #expect(names.insert(corpus).inserted, "duplicate corpus \(corpus)")
            let language = try #require(e["language"] as? String)
            #expect(["en", "zh", "ja"].contains(language))
            #expect(e["model"] as? String == "large-v3-turbo")
            let metric = try #require(e["metric"] as? String)
            #expect(["cer", "wer"].contains(metric))
            // zh selects CER; en selects WER (spec: metric selected by language).
            if language == "zh" || language == "ja" { #expect(metric == "cer") }
            if language == "en" { #expect(metric == "wer") }
            let golden = try #require(e["golden"] as? Double)
            #expect(golden >= 0)
            let tolerance = try #require(e["tolerance"] as? Double)
            #expect(tolerance > 0)
            // Accuracy only — no machine-dependent speed figures (design D1).
            #expect(e["rtf"] == nil)
            #expect(e["times_realtime"] == nil)
        }
    }

    @Test func `baseline covers all three languages symmetrically`() throws {
        let url = Self.repoRoot.appendingPathComponent("benchmarks/baseline.json")
        let data = try Data(contentsOf: url)
        let entries = try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let byLang = Dictionary(grouping: entries, by: { $0["language"] as? String ?? "?" })
        for lang in ["en", "zh", "ja"] {
            #expect((byLang[lang]?.count ?? 0) >= 3, "\(lang) below 3 corpora")
        }
        // The Chinese corpora are the Traditional set — Common Voice zh-TW (#34).
        let zhNames = (byLang["zh"] ?? []).compactMap { $0["corpus"] as? String }
        #expect(zhNames.allSatisfy { $0.hasPrefix("cv-zhtw-") })
    }

    // MARK: - compare stage (spec: Regression gate fails on accuracy regression)

    private func runCompare(baseline: [[String: Any]], measured: [[String: Any]]) throws -> (
        exit: Int32, output: String
    ) {
        let script = Self.repoRoot.appendingPathComponent("scripts/lib/baseline-compare.py")
        let input = try JSONSerialization.data(
            withJSONObject: ["baseline": baseline, "measured": measured])
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [script.path]
        let inPipe = Pipe()
        let outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = outPipe
        try p.run()
        inPipe.fileHandleForWriting.write(input)
        inPipe.fileHandleForWriting.closeFile()
        let out = String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, out)
    }

    /// Feed the compare stage RAW json text. Needed because the fail-open
    /// payloads in #134 cannot be built with JSONSerialization: bare `NaN` /
    /// `Infinity` are not legal JSON, and Foundation refuses to emit them —
    /// yet Python's `json.load` accepts both, which is precisely the hole.
    private func runCompareRaw(_ json: String) throws -> (exit: Int32, output: String) {
        let script = Self.repoRoot.appendingPathComponent("scripts/lib/baseline-compare.py")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [script.path]
        let inPipe = Pipe()
        let outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = outPipe
        try p.run()
        inPipe.fileHandleForWriting.write(Data(json.utf8))
        inPipe.fileHandleForWriting.closeFile()
        let out = String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, out)
    }

    /// One baseline entry + one measured entry, with `golden` / `tolerance` /
    /// `error_rate` injected as raw JSON tokens.
    private func payload(golden: String, tolerance: String, errorRate: String) -> String {
        """
        {"baseline":[{"corpus":"c1","language":"en","model":"large-v3-turbo",\
        "metric":"wer","golden":\(golden),"tolerance":\(tolerance)}],\
        "measured":[{"corpus":"c1","metric":"wer","error_rate":\(errorRate)}]}
        """
    }

    private let entry: [String: Any] = [
        "corpus": "c1", "language": "zh", "model": "large-v3-turbo",
        "metric": "cer", "golden": 0.10, "tolerance": 0.02,
    ]

    @Test func `within tolerance passes`() throws {
        let r = try runCompare(
            baseline: [entry],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.119]])
        #expect(r.exit == 0)
    }

    @Test func `regression beyond tolerance fails and names the corpus`() throws {
        let r = try runCompare(
            baseline: [entry],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.121]])
        #expect(r.exit != 0)
        #expect(r.output.contains("c1"))
        #expect(r.output.contains("0.1"))  // golden + measured figures surface
    }

    @Test func `improvement passes`() throws {
        let r = try runCompare(
            baseline: [entry],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.03]])
        #expect(r.exit == 0)
    }

    @Test func `a measured corpus with no baseline entry is a gate error`() throws {
        let r = try runCompare(
            baseline: [entry],
            measured: [
                ["corpus": "c1", "metric": "cer", "error_rate": 0.10],
                ["corpus": "orphan", "metric": "cer", "error_rate": 0.01],
            ])
        #expect(r.exit != 0)
        #expect(r.output.contains("orphan"))
    }

    @Test func `a baseline entry that was never measured is a gate error`() throws {
        let r = try runCompare(baseline: [entry], measured: [])
        #expect(r.exit != 0)
        #expect(r.output.contains("c1"))
    }

    @Test func `duplicate corpus names are a gate error, never last-wins`() throws {
        // A dict keyed by corpus would silently shadow duplicates; the compare
        // stage must surface them instead (#34 verify).
        let r = try runCompare(
            baseline: [entry, entry],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.10]])
        #expect(r.exit != 0)
        #expect(r.output.contains("duplicate"))

        let m = try runCompare(
            baseline: [entry],
            measured: [
                ["corpus": "c1", "metric": "cer", "error_rate": 0.10],
                ["corpus": "c1", "metric": "cer", "error_rate": 0.01],
            ])
        #expect(m.exit != 0)
        #expect(m.output.contains("duplicate"))
    }

    @Test func `speed differences never trip the gate`() throws {
        // Same accuracy, wildly different speed field — must pass (design D1:
        // speed is machine-dependent and is not gated).
        let r = try runCompare(
            baseline: [entry],
            measured: [
                [
                    "corpus": "c1", "metric": "cer", "error_rate": 0.10,
                    "times_realtime": 0.01,
                ]
            ])
        #expect(r.exit == 0)
    }

    // MARK: - baseline values reaching the CI log (#117)

    @Test func `an unknown metric is a gate error, not a label nobody checks`() throws {
        // metric was the one rendered field validated NOWHERE: the worklist
        // stage checks corpus and language, and unlike golden/tolerance it
        // never passes through float(). A bounded vocabulary makes a bad value
        // loud instead of decorative.
        var hostile = entry
        hostile["metric"] = "cer\u{1B}[32m\rFAKE ALL-PASS"
        let r = try runCompare(
            baseline: [hostile],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.10]])
        #expect(r.exit != 0)
        #expect(r.output.contains("unknown metric"))
    }

    @Test func `control characters never reach the log, even on the passing path`() throws {
        // Defense in depth at the RENDER boundary: language passes the worklist
        // whitelist in the gate, but this script is a separate entry point that
        // re-validates nothing. The payload repaints a CI line — CR returns the
        // cursor and the SGR turns it green — so a human reading the log to
        // approve a release sees a forged verdict. Escaped, it is inert AND
        // still diagnosable.
        var hostile = entry
        hostile["language"] = "zh\u{1B}[32m\rFAKE ALL-PASS"
        let r = try runCompare(
            baseline: [hostile],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.10]])
        #expect(r.exit == 0, "a hostile label must not change the verdict")
        #expect(!r.output.contains("\u{1B}"), "ANSI escape reached the log")
        #expect(!r.output.contains("\r"), "carriage return reached the log")
        #expect(r.output.contains("\\x1b"), "the offending bytes should stay visible")
    }

    // MARK: - fail-OPEN (#134): the gate reporting exit 0 on a real regression
    //
    // These are categorically worse than a noisy log. A gate that says "pass"
    // when it should say "fail" is not a weakened gate, it is an absent one
    // that still produces the reassuring output of a present one.

    @Test func `a non-finite golden cannot make a real regression pass`() throws {
        // measured 0.99 against golden 0.10 is a catastrophic regression.
        // NaN makes `diff > tol` false — every comparison against NaN is false —
        // so the gate printed a green check and exited 0.
        for token in ["NaN", "Infinity", "-Infinity", "1e999"] {
            let r = try runCompareRaw(payload(golden: token, tolerance: "0.02", errorRate: "0.99"))
            #expect(r.exit != 0, "golden \(token) let a 0.99-vs-0.10 regression pass")
            #expect(r.output.contains("GATE ERROR"), "golden \(token) produced no gate error")
        }
    }

    @Test func `a non-finite value spelled as a JSON string is caught too`() throws {
        // The subtle half: `{"golden": "NaN"}` is a legal JSON *string*, so
        // `json.load(parse_constant=...)` never fires — but `float("NaN")`
        // still yields nan. Validation must therefore happen AFTER conversion,
        // not by trying to reject the literal at parse time.
        for token in ["\"NaN\"", "\"Infinity\"", "\"1e999\""] {
            let r = try runCompareRaw(payload(golden: token, tolerance: "0.02", errorRate: "0.99"))
            #expect(r.exit != 0, "golden \(token) (string form) let a regression pass")
        }
    }

    @Test func `a non-finite measured error rate is a gate error, not a pass`() throws {
        let r = try runCompareRaw(payload(golden: "0.05", tolerance: "0.02", errorRate: "NaN"))
        #expect(r.exit != 0)
        #expect(r.output.contains("GATE ERROR"))
    }

    @Test func `a tolerance large enough to swallow any regression is itself an error`() throws {
        // The path that needs no non-finite number at all, and is therefore the
        // harder one to notice: a wide tolerance renders a 94-point regression
        // as an ordinary pass line.
        for token in ["1e308", "0.9", "1.0", "42"] {
            let r = try runCompareRaw(payload(golden: "0.05", tolerance: token, errorRate: "0.99"))
            #expect(r.exit != 0, "tolerance \(token) swallowed a 0.99-vs-0.05 regression")
            #expect(r.output.contains("GATE ERROR"), "tolerance \(token) produced no gate error")
        }
    }

    @Test func `a non-positive tolerance is rejected rather than silently gating everything`()
        throws
    {
        for token in ["0", "-0.02"] {
            let r = try runCompareRaw(payload(golden: "0.05", tolerance: token, errorRate: "0.05"))
            #expect(r.exit != 0, "tolerance \(token) accepted")
        }
    }

    @Test func `a garbage numeric field fails cleanly instead of raising`() throws {
        // `float("abc")` raises ValueError. A traceback is not a verdict — the
        // gate must say which corpus and which field, on stdout, like every
        // other gate error.
        let r = try runCompareRaw(payload(golden: "\"abc\"", tolerance: "0.02", errorRate: "0.05"))
        #expect(r.exit != 0)
        #expect(r.output.contains("GATE ERROR"), "expected a gate error, got: \(r.output)")
        #expect(!r.output.contains("Traceback"), "raised instead of reporting")
        #expect(r.output.contains("c1"), "the failing corpus must be named")
    }

    @Test func `the passing line shows the tolerance it was judged against`() throws {
        // Auditing a PASS is the whole point of this log, and the one number
        // that could expose a rigged pass — the threshold — appeared only on
        // FAILING lines. A reader checking a green run had no way to see that
        // the bar had been lowered to meet it.
        let r = try runCompare(
            baseline: [entry],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.11]])
        #expect(r.exit == 0)
        #expect(r.output.contains("tolerance"), "pass line hides its own threshold")
        #expect(r.output.contains("0.0200"), "the tolerance VALUE must be visible, not just the word")
    }

    @Test func `the real committed baseline passes the new numeric validation`() throws {
        // The bounds must not reject the file the gate actually runs on.
        let url = Self.repoRoot.appendingPathComponent("benchmarks/baseline.json")
        let data = try Data(contentsOf: url)
        let entries = try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let measured = entries.map {
            ["corpus": $0["corpus"]!, "metric": $0["metric"]!, "error_rate": $0["golden"]!]
        }
        let r = try runCompare(baseline: entries, measured: measured)
        #expect(r.exit == 0, "the committed baseline was rejected: \(r.output)")
    }
}
