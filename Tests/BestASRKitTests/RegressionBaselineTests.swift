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
}
