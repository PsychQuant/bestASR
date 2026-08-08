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

    private func runCompare(
        baseline: [[String: Any]], measured: [[String: Any]],
        expectedCorpora: [String]? = nil
    ) throws -> (
        exit: Int32, output: String
    ) {
        let script = Self.repoRoot.appendingPathComponent("scripts/lib/baseline-compare.py")
        var payload: [String: Any] = ["baseline": baseline, "measured": measured]
        if let expectedCorpora { payload["expected_corpora"] = expectedCorpora }
        let input = try JSONSerialization.data(withJSONObject: payload)
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

    @Test func `a run that compared nothing is not a pass`() throws {
        // #134 verify (cross-model leg): with both sides empty every loop is a
        // no-op, so the gate printed "all 0 corpora within tolerance" and exited
        // 0. A fetch that produced no measurements, or a worklist that silently
        // emptied, therefore read as "this release is safe".
        let r = try runCompareRaw(#"{"baseline":[],"measured":[]}"#)
        #expect(r.exit != 0, "an empty comparison reported success")
        #expect(r.output.contains("GATE ERROR"))
    }

    @Test func `a boolean is not laundered into a measurement`() throws {
        // `bool` subclasses `int`, so `float(true)` is 1.0 and a bare `true`
        // passed every bound as an ordinary number.
        let r = try runCompareRaw(payload(golden: "true", tolerance: "0.02", errorRate: "0.99"))
        #expect(r.exit != 0)
        #expect(r.output.contains("GATE ERROR"))
    }

    @Test func `a boolean false is not laundered into a perfect score`() throws {
        // The case above stopped proving anything once `golden` was bounded at
        // 0.5: `float(true)` is 1.0, which the bounds now refuse before the type
        // check is ever consulted. Every bool position is redundantly covered
        // that way — except this one. `float(false)` is **0.0**, which is inside
        // every bound, so the type guard is the only thing standing between a
        // bare `false` and a measurement of *zero errors*.
        //
        // That is also the only direction that manufactures a PASS rather than a
        // failure: with the guard deleted this payload prints
        // `✓ … golden 0.0500 → measured 0.0000 (-0.0500 ≤ tolerance 0.0200)`
        // and exits 0.
        let r = try runCompareRaw(payload(golden: "0.05", tolerance: "0.02", errorRate: "false"))
        #expect(r.exit != 0, "a boolean false was accepted as a perfect measurement")
        #expect(r.output.contains("GATE ERROR"))
        #expect(r.output.contains("boolean"))
    }

    @Test func `a boolean false is not laundered into a golden either`() throws {
        // The other verdict-flipping bool position, and a different mechanism
        // worth keeping distinct from the one above. `golden: false` → 0.0 makes
        // the THRESHOLD maximally strict, so removing the guard flips the exit
        // code while leaving the accuracy comparison conservative: a type hole.
        // `error_rate: false` → 0.0 makes the MEASUREMENT a perfect score, so an
        // arbitrarily bad system is admitted as flawless: an accuracy hole.
        // Only the second is a fail-open in substance; both are worth pinning.
        let r = try runCompareRaw(payload(golden: "false", tolerance: "0.02", errorRate: "0.01"))
        #expect(r.exit != 0, "a boolean false was accepted as a golden of zero")
        #expect(r.output.contains("GATE ERROR"))
        #expect(r.output.contains("boolean"))
    }

    @Test func `a measurement is never judged against a different metric's golden`() throws {
        // metric was validated on the baseline side only and never compared
        // across, so a WER measurement could be judged against a CER golden —
        // passing or failing on a number that means something else.
        let r = try runCompareRaw(
            #"{"baseline":[{"corpus":"c1","language":"zh","model":"m","metric":"cer","golden":0.05,"tolerance":0.02}],"measured":[{"corpus":"c1","metric":"wer","error_rate":0.06}]}"#)
        #expect(r.exit != 0, "a wer measurement was judged against a cer golden")
        #expect(r.output.contains("GATE ERROR"))
    }

    @Test func `a repeated JSON key cannot hide the real threshold`() throws {
        // Python keeps the LAST value for a duplicate key, so
        // {"golden": 0.9, "golden": 0.01} silently becomes 0.01 — a decoy in
        // the one file whose purpose is to be auditable by reading it. The
        // duplicate-CORPUS check does not see this: that compares entries, this
        // is one key repeated inside a single entry.
        let r = try runCompareRaw(
            #"{"baseline":[{"corpus":"c1","language":"en","model":"m","metric":"wer","golden":0.9,"golden":0.01,"tolerance":0.02}],"measured":[{"corpus":"c1","metric":"wer","error_rate":0.02}]}"#)
        #expect(r.exit != 0, "a duplicate key silently took the last value")
        #expect(r.output.contains("duplicate key"))
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

    // MARK: - the effective threshold is `golden + tolerance` (#134 verify, F1)

    // `diff = actual - golden` and the test is `diff > tol`, i.e. the gate
    // passes anything at or below `golden + tolerance`. The two fields are one
    // lever, so bounding only `tolerance` leaves the sum — the number that
    // actually decides the verdict — unbounded in the other direction.

    @Test func `an inflated golden cannot buy slack a tolerance would be refused`() throws {
        // The R1 reproduction, kept as a regression lock. Note which mechanism
        // actually fires: `golden` reuses the effective threshold as its
        // per-field ceiling, so 2.0 is refused there and this payload never
        // reaches the sum check. It pins the verdict, not the sum path — the
        // case below is what covers the sum.
        let r = try runCompareRaw(payload(golden: "2.0", tolerance: "0.02", errorRate: "0.99"))
        #expect(r.exit != 0, "a golden of 2.0 waved through a 0.99 measurement")
        #expect(r.output.contains("GATE ERROR"))
        #expect(!r.output.contains("Traceback"))
    }

    @Test func `the sum path fires for a golden that clears its own ceiling`() throws {
        // `golden` 0.4 is comfortably inside the per-field ceiling and only the
        // SUM (0.4 + 0.15 = 0.55) exceeds the bound, so this is the case that
        // exercises the sum check rather than shadowing it. Asserting the
        // distinguishing message is the point: without it the test could not
        // tell which of the two mechanisms rejected the payload.
        let r = try runCompareRaw(payload(golden: "0.4", tolerance: "0.15", errorRate: "0.5"))
        #expect(r.exit != 0)
        #expect(
            r.output.contains("golden + tolerance is"),
            "expected the sum-bound message, got: \(r.output)")
    }

    @Test func `the sum bound catches the modest inflation the bound on golden alone misses`()
        throws
    {
        // The realistic shape: no extreme value anywhere, an innocuous-looking
        // pass line. `golden` alone clears its own ceiling; only the sum does not.
        let r = try runCompareRaw(payload(golden: "0.49", tolerance: "0.02", errorRate: "0.50"))
        #expect(r.exit != 0, "golden 0.49 + tolerance 0.02 exceeded the effective-threshold bound")
        #expect(r.output.contains("GATE ERROR"))
    }

    @Test func `the effective-threshold bound is inclusive at its edge`() throws {
        // 0.48 + 0.02 == 0.5 exactly: accepted, so the bound refuses only what
        // is strictly beyond it (consistent with the `≤ tolerance` rendering).
        let r = try runCompareRaw(payload(golden: "0.48", tolerance: "0.02", errorRate: "0.49"))
        #expect(r.exit == 0, "the sum bound rejected its own boundary: \(r.output)")
    }

    // MARK: - the per-field ceilings are load-bearing (#134 verify, F4)

    // Both were removable with a green suite: every non-finite payload is
    // caught earlier by `math.isfinite`, and no test used a FINITE value above
    // either ceiling. A guard no test can distinguish from its absence is not
    // a guard. (`golden`'s own ceiling failed that test even after the sum
    // bound landed — the sum subsumes it entirely — so it was deleted rather
    // than given a test written to justify it. `golden` is now bounded by the
    // effective threshold, which is the number that actually decides.)

    @Test func `a finite golden beyond any usable threshold is refused by name`() throws {
        let r = try runCompareRaw(payload(golden: "2.001", tolerance: "0.02", errorRate: "0.01"))
        #expect(r.exit != 0)
        #expect(r.output.contains("GATE ERROR"))
        // Assert the DISTINGUISHING substring, not just "golden". The sum-bound
        // message is "golden + tolerance is …", so `contains("golden")` is
        // satisfied by either path and cannot verify the "by name" this test is
        // named for — it would pass with the per-field bound deleted.
        #expect(
            r.output.contains("must be at most"),
            "expected the per-field message, got: \(r.output)")
    }

    @Test func `a tolerance inside the sum bound is still refused on its own terms`() throws {
        // The region where TOLERANCE_MAX does work the sum bound cannot:
        // 0.1 + 0.3 = 0.4 clears the effective-threshold ceiling, but a
        // tolerance of 0.3 means "accept a 30-point regression on this corpus"
        // regardless of what it actually scores. A large tolerance is worse
        // than a large golden of the same size, because it applies whatever
        // the measurement turns out to be — hence the tighter bound.
        let r = try runCompareRaw(payload(golden: "0.1", tolerance: "0.3", errorRate: "0.2"))
        #expect(r.exit != 0, "a 30-point tolerance passed because the sum happened to fit")
        #expect(r.output.contains("GATE ERROR"))
        // `contains("tolerance")` alone can never fail here — the PASSING line
        // renders "… ≤ tolerance 0.3000", so it holds with the ceiling removed.
        #expect(
            r.output.contains("tolerance must be at most"),
            "expected the tolerance ceiling message, got: \(r.output)")
    }

    @Test func `a finite error rate above the per-field ceiling is refused`() throws {
        let r = try runCompareRaw(payload(golden: "0.05", tolerance: "0.02", errorRate: "101"))
        #expect(r.exit != 0)
        #expect(r.output.contains("error_rate"))
        #expect(r.output.contains("GATE ERROR"))
    }

    // MARK: - a traceback is not a verdict, for integers too (#134 verify, F5)

    @Test func `a huge bare integer fails as a named gate error, not an OverflowError`() throws {
        // `float()` raises OverflowError on a large Python int — neither
        // TypeError nor ValueError, so it escaped the converter's except
        // clause and reached the CI log as a stack trace where the verdict
        // belongs. Reproduces on every CPython (the 4300-digit int↔str cap is
        // far above this literal and never fires).
        let huge = "1" + String(repeating: "0", count: 400)
        let r = try runCompareRaw(payload(golden: huge, tolerance: "0.02", errorRate: "0.99"))
        #expect(r.exit != 0)
        #expect(!r.output.contains("Traceback"), "raw traceback instead of a verdict: \(r.output)")
        #expect(r.output.contains("GATE ERROR"))
        // The echo cap is a guard too, and the three assertions above hold with
        // or without it — so without this one it would be exactly the "constant
        // no test can distinguish from its absence" the compare script condemns.
        #expect(r.output.contains("(401 chars)"), "the rejected value was not truncated")
        #expect(!r.output.contains(String(repeating: "0", count: 200)))
    }

    // MARK: - completeness: a truncated comparison is not a pass (#134 verify, F2)

    // The empty-set guard closed cardinality 0. It did not close 1-of-N: both
    // sides of the comparison are derived from the same `baseline.json`, so
    // deleting entries shrinks the baseline, the worklist and the measured set
    // together and the gate reports "all 1 corpora within tolerance".
    // The anchor has to come from outside that file.

    @Test func `a baseline missing corpora the provenance record pins is a gate error`() throws {
        let r = try runCompare(
            baseline: [entry],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.10]],
            expectedCorpora: ["c1", "c2", "c3"])
        #expect(r.exit != 0, "a 1-of-3 comparison reported success")
        #expect(r.output.contains("GATE ERROR"))
        #expect(r.output.contains("c2"))
        #expect(r.output.contains("c3"))
    }

    @Test func `a baseline carrying corpora the provenance record does not pin is a gate error`()
        throws
    {
        // The other direction: an entry added to baseline.json without
        // re-seeding is equally a divergence between the two files.
        let r = try runCompare(
            baseline: [entry],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.10]],
            expectedCorpora: [])
        #expect(r.exit != 0)
        #expect(r.output.contains("GATE ERROR"))
        #expect(r.output.contains("c1"))
    }

    @Test func `a matching corpus set passes and says the completeness check ran`() throws {
        let r = try runCompare(
            baseline: [entry],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.10]],
            expectedCorpora: ["c1"])
        #expect(r.exit == 0, "\(r.output)")
        // The second half of this test's name used to be unverifiable: a
        // satisfied anchor printed nothing, so the only evidence it ran was the
        // absence of the NOTE. The script now says so positively, and this
        // asserts it — otherwise the name claims more than the test checks.
        #expect(
            r.output.contains("completeness:") && r.output.contains("verified"),
            "a satisfied anchor left no trace: \(r.output)")
    }

    @Test func `the gate script actually wires the anchor into the payload it pipes`() throws {
        // The seam neither the compare-stage tests nor the file-coupling test
        // reach. Those inject `expected_corpora` as a parameter and compare the
        // two JSON files in Swift; NEITHER runs `regression-gate.sh`, and
        // `ci.yml` deliberately does not run the gate either. So renaming one
        // token in the assembler — `.get("corpora")` → `.get("corpora_SET")` —
        // silently reverts the whole guard with a 100% green suite.
        //
        // This extracts the assembler heredoc from the real script and runs it,
        // so a change to that block has to survive a test.
        let root = Self.repoRoot
        let gate = try String(
            contentsOf: root.appendingPathComponent("scripts/regression-gate.sh"), encoding: .utf8)
        let body = try #require(
            gate.range(of: "import json, os, sys").flatMap { start in
                gate.range(of: "\nPY\n", range: start.lowerBound..<gate.endIndex).map {
                    String(gate[start.lowerBound..<$0.lowerBound])
                }
            }, "could not extract the assembler heredoc from regression-gate.sh")

        let results = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idd134-wiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: results) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [
            "-c", body,
            root.appendingPathComponent("benchmarks/baseline.json").path,
            results.path,
            root.appendingPathComponent("benchmarks/baseline-meta.json").path,
        ]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let payload = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "assembler emitted no JSON object")
        let anchor = try #require(
            payload["expected_corpora"] as? [String],
            "the gate did not put expected_corpora in the payload — the anchor is not wired")
        let committed = try #require(
            try JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: root.appendingPathComponent("benchmarks/baseline.json")))
                as? [[String: Any]])
        #expect(Set(anchor) == Set(committed.compactMap { $0["corpus"] as? String }))
    }

    /// Run `regression-gate.sh`'s meta pre-flight in isolation against a given
    /// baseline path and `BESTASR_BASELINE_META`, returning its exit status.
    /// Extracted from the script so the block cannot drift away from its test.
    private func runMetaPreflight(baseline: String, meta: String) throws -> (
        exit: Int32, output: String
    ) {
        let gate = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/regression-gate.sh"),
            encoding: .utf8)
        let lines = gate.components(separatedBy: "\n")
        guard
            let defLine = lines.firstIndex(where: { $0.hasPrefix("DEFAULT_BASELINE=") }),
            let start = lines.firstIndex(where: { $0.hasPrefix("META=\"${BESTASR_BASELINE_META") }),
            let end = lines.firstIndex(where: { $0.hasPrefix("CACHE_ROOT=") })
        else { throw CocoaError(.fileReadCorruptFile) }
        // `$0` must be the real script path: DEFAULT_BASELINE resolves the repo
        // root from `dirname "$0"`, so passing anything else silently sends every
        // case down the "overridden baseline" branch and the test proves nothing.
        let script = """
            set -euo pipefail
            BASELINE="$1"
            TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
            \(lines[defLine])
            \(lines[start..<end].joined(separator: "\n"))
            echo "PREFLIGHT OK"
            """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [
            "-c", script,
            Self.repoRoot.appendingPathComponent("scripts/regression-gate.sh").path,
            baseline,
        ]
        var env = ProcessInfo.processInfo.environment
        env["BESTASR_BASELINE_META"] = meta
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let text = String(
            data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, text)
    }

    @Test func `the gate refuses to run the repo baseline without a usable anchor`() throws {
        // The counterpart the compare-stage test below cannot provide. Until
        // both exist, the suite asserts only the permissive half and the
        // degradation reads as the specification.
        let real = Self.repoRoot.appendingPathComponent("benchmarks/baseline.json").path
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idd134-meta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let metaURL = Self.repoRoot.appendingPathComponent("benchmarks/baseline-meta.json")
        var meta = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as? [String: Any])

        // Sanity: the committed pair must pass, or the cases below prove nothing.
        let ok = try runMetaPreflight(baseline: real, meta: metaURL.path)
        #expect(ok.exit == 0, "the committed meta was rejected: \(ok.output)")

        for (name, mutate) in [
            ("absent", { (_: inout [String: Any]) in }),
            ("no corpora key", { (m: inout [String: Any]) in m["corpora"] = nil }),
            ("corpora null", { (m: inout [String: Any]) in m["corpora"] = NSNull() }),
            ("corpora not a list", { (m: inout [String: Any]) in m["corpora"] = 5 }),
            ("corpora empty", { (m: inout [String: Any]) in m["corpora"] = [String]() }),
            ("corpora duplicated", { (m: inout [String: Any]) in m["corpora"] = ["jfk", "jfk"] }),
        ] {
            let path: String
            if name == "absent" {
                path = tmp.appendingPathComponent("does-not-exist.json").path
            } else {
                var m = meta
                mutate(&m)
                let f = tmp.appendingPathComponent("meta-\(UUID().uuidString).json")
                try JSONSerialization.data(withJSONObject: m).write(to: f)
                path = f.path
            }
            let r = try runMetaPreflight(baseline: real, meta: path)
            #expect(r.exit != 0, "meta '\(name)' was accepted for the repo baseline: \(r.output)")
            #expect(r.output.contains("gate error"), "\(name): \(r.output)")
        }

        // An overridden baseline is a deliberate act by a caller supplying their
        // own inputs — warn, do not refuse, or ordinary local triage breaks.
        let overridden = try runMetaPreflight(
            baseline: tmp.appendingPathComponent("custom.json").path,
            meta: tmp.appendingPathComponent("does-not-exist.json").path)
        #expect(overridden.exit == 0)
        #expect(overridden.output.contains("warning"))
        _ = meta
    }

    @Test func `an absent anchor is tolerated by the filter and refused by the gate`() throws {
        // Deliberately asserts exit 0: `baseline-compare.py` is a stdin filter
        // and cannot know whether it was handed a whole sweep, so refusing here
        // would break every direct invocation. The NOTE is what stops silence
        // from reading as health.
        //
        // The invariant belongs one layer up, where it can be enforced:
        // `regression-gate.sh` DOES know which baseline it is running and now
        // exits non-zero when the repo's own meta is missing or malformed. Read
        // this test together with that conditional — on its own it would be
        // pinning the degradation in place.
        let r = try runCompare(
            baseline: [entry],
            measured: [["corpus": "c1", "metric": "cer", "error_rate": 0.10]])
        #expect(r.exit == 0)
        #expect(
            r.output.lowercased().contains("completeness"),
            "a run with no expected-corpus anchor did not disclose it: \(r.output)")
    }

    @Test func `the committed baseline matches the corpus set pinned in baseline-meta`() throws {
        // The coupling itself: truncating baseline.json now requires a second,
        // deliberate edit to a file whose name is `baseline-meta`.
        let root = Self.repoRoot
        let entries = try #require(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appendingPathComponent("benchmarks/baseline.json")))
                as? [[String: Any]])
        let meta = try #require(
            try JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: root.appendingPathComponent("benchmarks/baseline-meta.json")))
                as? [String: Any])
        let pinned = try #require(meta["corpora"] as? [String])
        let actual = entries.compactMap { $0["corpus"] as? String }
        let onlyBaseline = Set(actual).subtracting(pinned).sorted()
        let onlyMeta = Set(pinned).subtracting(actual).sorted()
        #expect(
            Set(actual) == Set(pinned),
            "baseline.json and baseline-meta.json disagree on the corpus set: only in baseline \(onlyBaseline), only in meta \(onlyMeta)"
        )
    }
}
