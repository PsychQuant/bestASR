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
        // #165 family-wide sweep — EXEMPT from SubprocessRunner, deliberately.
        //
        // This is the one spawn site the shared runner cannot serve: it feeds
        // the child on stdin, and SubprocessRunner has no stdin support —
        // tracked as item 4 of #170's Expected list, NOT the descendant-kill gap
        // #170 is named for (#165 round-2 M5 flagged that miscitation). Rather
        // than pretend, the shape is fixed in place, bounded below, and the
        // exemption is registered in SpawnSiteSweepTests with its retained risk.
        //
        // The bug being fixed here is the stdin-side mirror of #158: writing the
        // whole payload before draining deadlocks once the input exceeds the
        // pipe buffer and the child starts emitting output — the child blocks
        // writing stdout, so it never drains our stdin, so our write never
        // returns. Drain concurrently with the write.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [script.path]
        let inPipe = Pipe()
        let outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = outPipe
        try p.run()

        final class DataBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value = Data()
            func set(_ d: Data) { lock.withLock { value = d } }
            var get: Data { lock.withLock { value } }
        }
        let outBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outBox.set(outPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        inPipe.fileHandleForWriting.write(input)
        inPipe.fileHandleForWriting.closeFile()

        // #165 round-2 N2: fixing the ordering deadlock left this site with no
        // deadline at all — `group.wait()` and `waitUntilExit()` were both
        // unbounded, and none of the callers carry a `.timeLimit` (which could
        // not preempt these anyway). "No deadline bounding the operation" is the
        // exact failure mode #91 → #158 → #165 kept recurring as, so leaving it
        // here would have re-created it in the one site the sweep exempted.
        //
        // Bounded wait with a kill escalation, mirroring SubprocessRunner. This
        // is not the shared helper — it cannot be, until #170 adds stdin — but
        // it does have to be bounded.
        let budget = DispatchTime.now() + .seconds(120)
        if group.wait(timeout: budget) == .timedOut {
            p.terminate()
            if group.wait(timeout: .now() + .seconds(2)) == .timedOut {
                kill(p.processIdentifier, SIGKILL)
                try? outPipe.fileHandleForReading.close()
                _ = group.wait(timeout: .now() + .seconds(2))
            }
            p.waitUntilExit()
            throw BestASRError.runtime(
                "baseline-compare.py exceeded its 120s budget and was terminated")
        }
        p.waitUntilExit()
        let out = String(data: outBox.get, encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
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
}
