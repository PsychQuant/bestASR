import Foundation
import Testing
@testable import BestASRKit

/// CommandCore with everything injected: mock engines, fixed host, temp store,
/// deterministic clock. No real backend, no real detection, no network.
private func makeCore(
    engines: [any Engine],
    cacheDir: URL,
    host: SystemInfo = Fixtures.m5Max
) -> CommandCore {
    CommandCore(
        engines: engines,
        detect: { host },
        store: BenchmarkStore(directory: cacheDir.appendingPathComponent("store")),
        probe: FakeClockProbe.probe()
    )
}

private enum FakeClockProbe {
    static func probe() -> MeasurementProbe {
        let clock = FakeClock(step: 1.0)
        return clock.probe()
    }
}

private let auto = SelectionRequest(
    profileName: "medium", backendOverride: nil, modelOverride: nil, requestedLanguage: "auto")

struct DiagnoseCommandTests {
    @Test func `diagnose prints environment and recommendation without needing audio`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let core = makeCore(engines: [MockEngine.fixed(.whisperKit)], cacheDir: dir)
        let output = try await core.diagnose()
        #expect(output.contains("Apple M5 Max"))
        #expect(output.contains("Recommendation:"))
        #expect(output.contains("whisperkit"))
        #expect(output.contains("Reason:"))
    }

    @Test func `diagnose still reports the environment when no backend is available`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let core = makeCore(
            engines: [MockEngine.fixed(.whisperKit, available: false)], cacheDir: dir)
        let output = try await core.diagnose()
        #expect(output.contains("Apple M5 Max"))
        #expect(output.contains("no ASR backend is available"))
    }
}

struct RecommendCommandTests {
    @Test func `recommend emits a single machine-readable JSON object`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let core = makeCore(engines: [MockEngine.fixed(.whisperKit)], cacheDir: dir)

        let output = try await core.recommendJSON(audioPath: audio, selection: auto)
        let object =
            try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        let json = try #require(object)
        for key in ["backend", "model", "quantization", "data_source", "reason", "warnings"] {
            #expect(json[key] != nil, "missing key \(key)")
        }
        #expect(json["data_source"] as? String == "cold_start_prior")
        #expect(json["measured"] is NSNull || json["measured"] == nil)
    }

    @Test func `recommend reflects benchmark data when the cache has a usable record`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        // Legacy flat cache seeded on purpose: the store's one-time migration
        // (spec benchmark-store) is the integration path under test here.
        let cache = BenchmarkCache(fileURL: dir.appendingPathComponent("benchmarks.json"))
        try cache.upsert([Fixtures.record(language: "zh")])  // chip matches Fixtures.m5Max
        let core = CommandCore(
            engines: [MockEngine.fixed(.whisperKit)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            probe: FakeClockProbe.probe()
        )

        let selection = SelectionRequest(
            profileName: "high", backendOverride: nil, modelOverride: nil,
            requestedLanguage: "zh")
        let output = try await core.recommendJSON(audioPath: audio, selection: selection)
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        #expect(json["data_source"] as? String == "measured")
        let measured = try #require(json["measured"] as? [String: Any])
        #expect(measured["metric_kind"] as? String == "cer")
        #expect(measured["error_rate"] as? Double == 0.05)
    }

    @Test func `recommend on a missing audio file is a usage error`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let core = makeCore(engines: [MockEngine.fixed(.whisperKit)], cacheDir: dir)
        do {
            _ = try await core.recommendJSON(audioPath: "/nonexistent.wav", selection: auto)
            Issue.record("expected a usage error")
        } catch let error as BestASRError {
            #expect(error.exitCode == 2)
        }
    }
}

struct TranscribeCommandTests {
    @Test func `transcribe writes the requested format to a derived path`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let core = makeCore(engines: [MockEngine.fixed(.whisperKit)], cacheDir: dir)

        let outcome = try await core.transcribe(
            audioPath: audio, selection: auto, formatName: "srt", outputPath: nil)
        #expect(outcome.format == "srt")
        #expect(outcome.outputPath.hasSuffix("clip.srt"))
        let written = try String(contentsOfFile: outcome.outputPath, encoding: .utf8)
        #expect(written.contains("-->"))
    }

    @Test func `transcribe defaults to txt and keeps the file free of explanations`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let core = makeCore(engines: [MockEngine.fixed(.whisperKit)], cacheDir: dir)

        let outcome = try await core.transcribe(
            audioPath: audio, selection: auto, formatName: "txt", outputPath: nil)
        let written = try String(contentsOfFile: outcome.outputPath, encoding: .utf8)
        #expect(written == "hello world")  // transcript only — no reasons in the file
        #expect(outcome.explanation.contains("because"))
        #expect(outcome.explanation.contains("cold start"))
    }
}

struct BenchmarkCommandTests {
    @Test func `benchmark prints a ranked table and persists results`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir, seconds: 2.0)
        let srt = dir.appendingPathComponent("truth.srt").path
        try "1\n00:00:00,000 --> 00:00:02,000\nhello world\n".write(
            toFile: srt, atomically: true, encoding: .utf8)
        let store = BenchmarkStore(directory: dir.appendingPathComponent("store"))
        let core = CommandCore(
            engines: [MockEngine.fixed(.whisperKit)],
            detect: { Fixtures.m5Max },
            store: store,
            probe: FakeClockProbe.probe()
        )

        let report = try await core.benchmark(
            audioPath: audio, referencePath: srt, language: "en",
            backendFilter: nil, modelFilter: ["tiny"], profileName: "medium", asJSON: false
        )
        #expect(report.contains("RANK"))
        #expect(report.contains("whisperkit"))
        let snapshot = try store.load()
        #expect(snapshot.measurements.count == 1)  // persisted (spec: benchmark-store)
        #expect(snapshot.measurements[0].errorRate == 0)  // mock says exactly "hello world"
        #expect(snapshot.models.count >= 30)  // grid seeded wholesale
    }

    @Test func `benchmark json mode emits machine-readable results`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir, seconds: 2.0)
        let srt = dir.appendingPathComponent("truth.srt").path
        try "1\n00:00:00,000 --> 00:00:02,000\nhello world\n".write(
            toFile: srt, atomically: true, encoding: .utf8)
        let core = makeCore(engines: [MockEngine.fixed(.whisperKit)], cacheDir: dir)

        let report = try await core.benchmark(
            audioPath: audio, referencePath: srt, language: "en",
            backendFilter: nil, modelFilter: ["tiny"], profileName: "medium", asJSON: true
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any])
        let results = try #require(json["results"] as? [[String: Any]])
        #expect(results.count == 1)
        #expect(results[0]["rank"] as? Int == 1)
    }

    @Test func `missing reference is a usage error raised before any transcription`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        // A failing engine would blow up IF transcription started — it must not.
        let core = makeCore(engines: [MockEngine.failing(.whisperKit)], cacheDir: dir)
        do {
            _ = try await core.benchmark(
                audioPath: audio, referencePath: "/nonexistent/truth.srt", language: "en",
                backendFilter: nil, modelFilter: nil, profileName: "medium", asJSON: false
            )
            Issue.record("expected a usage error")
        } catch let error as BestASRError {
            #expect(error.exitCode == 2)  // usage, not runtime
        }
    }

    @Test func `all candidates failing is a runtime failure`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir, seconds: 2.0)
        let srt = dir.appendingPathComponent("truth.srt").path
        try "1\n00:00:00,000 --> 00:00:02,000\nhi\n".write(
            toFile: srt, atomically: true, encoding: .utf8)
        let core = makeCore(engines: [MockEngine.failing(.whisperKit)], cacheDir: dir)

        do {
            _ = try await core.benchmark(
                audioPath: audio, referencePath: srt, language: "en",
                backendFilter: nil, modelFilter: ["tiny"], profileName: "medium", asJSON: false
            )
            Issue.record("expected a runtime error")
        } catch let error as BestASRError {
            #expect(error.exitCode == 1)  // runtime failure per spec
        }
    }
}

struct ListCommandTests {
    @Test func `list-backends shows availability per backend`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let core = makeCore(
            engines: [
                MockEngine.fixed(.whisperKit, available: true),
                MockEngine.fixed(.whisperCpp, available: false),
            ],
            cacheDir: dir
        )
        let output = await core.listBackends()
        #expect(output.contains("whisperkit"))
        #expect(output.contains("available"))
        #expect(output.contains("whisper.cpp"))
        #expect(output.contains("not installed"))
    }

    @Test func `list-models lists sizes with quantization variants`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let core = makeCore(engines: [], cacheDir: dir)
        let output = core.listModels()
        #expect(output.contains("tiny"))
        #expect(output.contains("large-v3"))
        #expect(output.contains("q5_1"))  // tiny/base/small row (HF-accurate, #5)
        #expect(output.contains("q5_0"))  // medium/large-tier row
    }
}

// MARK: - Context wiring (tasks 3.1/3.2; spec context-calibration + cli MODIFIED)

private func makeContextFixture(in dir: URL) throws -> String {
    let ctx = dir.appendingPathComponent("ctx")
    try FileManager.default.createDirectory(at: ctx, withIntermediateDirectories: true)
    try """
        {"version":1,"terms":["benchmark-driven","CoreML"],
         "names":[{"name":"鄭澈","aliases":["Che"],"role":"主持人"}]}
        """.write(to: ctx.appendingPathComponent("context.json"), atomically: true, encoding: .utf8)
    try "WhisperKit\n".write(
        to: ctx.appendingPathComponent("terms.txt"), atomically: true, encoding: .utf8)
    try Data("fake".utf8).write(to: ctx.appendingPathComponent("lecture.pdf"))
    return ctx.path
}

/// Captures the options each transcription received — parallel-test safe.
final class OptionsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [TranscribeOptions] = []
    func append(_ options: TranscribeOptions) {
        lock.lock(); defer { lock.unlock() }
        stored.append(options)
    }
    var all: [TranscribeOptions] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

private func capturingEngine(_ box: OptionsBox) -> MockEngine {
    MockEngine(id: .whisperKit, available: true) { _, options in
        box.append(options)
        return RawTranscription(
            segments: [.init(start: 0.0, end: 2.5, text: "hello world")],
            language: "en", duration: 2.5)
    }
}

struct ContextCommandTests {
    @Test func `Explicit context directory feeds the transcription and explain discloses usage`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let ctxDir = try makeContextFixture(in: dir)
        let box = OptionsBox()
        let core = CommandCore(
            engines: [capturingEngine(box)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            probe: FakeClockProbe.probe()
        )
        let selection = SelectionRequest(
            profileName: "medium", backendOverride: nil, modelOverride: nil,
            requestedLanguage: "auto", contextDir: ctxDir)

        let outcome = try await core.transcribe(
            audioPath: audio, selection: selection, formatName: "txt", outputPath: nil)

        // Prompt reached the engine, names first (spec worked-example ordering).
        let prompt = try #require(box.all.first?.prompt)
        #expect(prompt.hasPrefix("鄭澈, Che"))
        #expect(prompt.contains("WhisperKit"))  // txt term merged after json terms

        // Explain discloses dir, injected, ignored (D9).
        #expect(outcome.explanation.contains("Context: \(ctxDir)"))
        #expect(outcome.explanation.contains("injected (5)"))
        #expect(outcome.explanation.contains("ignored: lecture.pdf"))
        #expect(outcome.explanation.contains("context-ingest"))

        // Transcript file stays free of explanations.
        let written = try String(contentsOfFile: outcome.outputPath, encoding: .utf8)
        #expect(written == "hello world")
    }

    @Test func `Zero impact when the context directory is empty`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let emptyCtx = dir.appendingPathComponent("empty-ctx")
        try FileManager.default.createDirectory(at: emptyCtx, withIntermediateDirectories: true)
        let box = OptionsBox()
        let core = CommandCore(
            engines: [capturingEngine(box)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            probe: FakeClockProbe.probe()
        )
        let selection = SelectionRequest(
            profileName: "medium", backendOverride: nil, modelOverride: nil,
            requestedLanguage: "auto", contextDir: emptyCtx.path)

        let outcome = try await core.transcribe(
            audioPath: audio, selection: selection, formatName: "txt", outputPath: nil)
        #expect(box.all.first?.prompt == nil)
        #expect(!outcome.explanation.contains("Context:"))
    }

    @Test func `recommend reason carries the context summary line`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let ctxDir = try makeContextFixture(in: dir)
        let core = CommandCore(
            engines: [MockEngine.fixed(.whisperKit)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            probe: FakeClockProbe.probe()
        )
        let selection = SelectionRequest(
            profileName: "medium", backendOverride: nil, modelOverride: nil,
            requestedLanguage: "auto", contextDir: ctxDir)
        let output = try await core.recommendJSON(audioPath: audio, selection: selection)
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let reasons = try #require(json["reason"] as? [String])
        #expect(reasons.contains { $0.contains("context:") && $0.contains("5 value(s) injected") })
    }
}
