import Foundation
import Testing
@testable import BestASRKit

/// A deterministic probe: each `now()` call advances by `step` seconds.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Double = 0
    let step: Double

    init(step: Double) { self.step = step }

    func probe(memoryGB: Double = 2.0) -> MeasurementProbe {
        MeasurementProbe(
            now: { [self] in
                lock.lock()
                defer { lock.unlock() }
                let value = time
                time += step
                return value
            },
            memoryGB: { memoryGB }
        )
    }
}

private let audio60s = AudioInfo(
    path: "clip.wav", duration: 60, format: "wav", sampleRate: 16000, channels: 1)

struct BenchmarkEnumerationTests {
    @Test func `Only available backends produce candidates, with a skip note`() async throws {
        let runner = BenchmarkRunner(
            engines: [
                MockEngine.fixed(.whisperKit, available: true),
                MockEngine.fixed(.whisperCpp, available: false),
            ],
            host: Fixtures.m5Max
        )
        let enumeration = try await runner.enumerateCandidates()
        #expect(!enumeration.candidates.isEmpty)
        #expect(enumeration.candidates.allSatisfy { $0.backend == .whisperKit })
        #expect(enumeration.notes.contains { $0.contains("whisper.cpp") && $0.contains("unavailable") })
    }

    @Test func `Explicit filters narrow the candidate set`() async throws {
        let runner = BenchmarkRunner(
            engines: [MockEngine.fixed(.whisperKit), MockEngine.fixed(.whisperCpp)],
            host: Fixtures.m5Max
        )
        let enumeration = try await runner.enumerateCandidates(
            backendFilter: ["whisperkit"], modelFilter: ["large-v3-turbo"])
        #expect(
            enumeration.candidates == [
                BenchmarkCandidate(
                    backend: .whisperKit, model: "large-v3-turbo", quantization: "default")
            ]
        )
    }

    @Test func `Unknown filter names are usage errors, not silent empties`() async {
        let runner = BenchmarkRunner(engines: [MockEngine.fixed(.whisperKit)], host: Fixtures.m5Max)
        await #expect(throws: BestASRError.self) {
            _ = try await runner.enumerateCandidates(backendFilter: ["wispakit"])
        }
        await #expect(throws: BestASRError.self) {
            _ = try await runner.enumerateCandidates(modelFilter: ["gigantic-v9"])
        }
    }
}

struct BenchmarkMeasurementTests {
    @Test func `RTF is timed-run seconds over audio seconds, warm-up separate`() async {
        // Each now() call advances 5s; a timing bracket is two calls → 5s of
        // wall-clock per transcribe. Audio is 60s → RTF must be 5/60 (spec SBE).
        let clock = FakeClock(step: 5.0)
        let runner = BenchmarkRunner(
            engines: [MockEngine.fixed(.whisperKit)],
            host: Fixtures.m5Max,
            probe: clock.probe()
        )
        let candidate = BenchmarkCandidate(
            backend: .whisperKit, model: "tiny", quantization: "default")
        let outcome = await runner.run(
            candidates: [candidate], notes: [], audio: audio60s,
            referenceText: "hello world", metricKind: .wer, language: "en"
        )
        let measured = try! #require(outcome.measured.first)
        #expect(abs(measured.record.rtf - 5.0 / 60.0) < 1e-9)
        #expect(measured.warmupSeconds == 5.0)  // separate figure, not in RTF
        #expect(measured.record.errorRate == 0)  // hypothesis matches reference
        #expect(measured.record.chip == Fixtures.m5Max.chip)
    }

    @Test func `One failing candidate does not abort the run`() async {
        let runner = BenchmarkRunner(
            engines: [MockEngine.fixed(.whisperKit), MockEngine.failing(.whisperCpp)],
            host: Fixtures.m5Max,
            probe: FakeClock(step: 1).probe()
        )
        let candidates = [
            BenchmarkCandidate(backend: .whisperKit, model: "tiny", quantization: "default"),
            BenchmarkCandidate(backend: .whisperCpp, model: "tiny", quantization: "q5_0"),
            BenchmarkCandidate(backend: .whisperKit, model: "small", quantization: "default"),
        ]
        let outcome = await runner.run(
            candidates: candidates, notes: [], audio: audio60s,
            referenceText: "hello world", metricKind: .wer, language: "en"
        )
        #expect(outcome.measured.count == 2)
        #expect(outcome.failures.count == 1)
        #expect(outcome.failures[0].candidate.backend == .whisperCpp)
        #expect(outcome.failures[0].reason.contains("decode error"))
    }

    @Test func `All candidates failing yields zero measurements`() async {
        let runner = BenchmarkRunner(
            engines: [MockEngine.failing(.whisperKit)],
            host: Fixtures.m5Max,
            probe: FakeClock(step: 1).probe()
        )
        let outcome = await runner.run(
            candidates: [
                BenchmarkCandidate(backend: .whisperKit, model: "tiny", quantization: "default")
            ],
            notes: [], audio: audio60s,
            referenceText: "hi", metricKind: .wer, language: "en"
        )
        #expect(outcome.measured.isEmpty)
        #expect(outcome.failures.count == 1)
    }
}

struct RankingTests {
    @Test func `Accuracy-first ranking under the accurate profile matches the spec table`() {
        // Spec SBE: wk large-v3-turbo (CER .05, 12x) #1; wcpp large-v3 q5 (.06, 6x) #2;
        // wcpp small q5 (.15, 20x) #3.
        let records = [
            Fixtures.record(backend: .whisperCpp, model: "small", quantization: "q5_0",
                            errorRate: 0.15, timesRealtime: 20),
            Fixtures.record(backend: .whisperKit, model: "large-v3-turbo",
                            errorRate: 0.05, timesRealtime: 12),
            Fixtures.record(backend: .whisperCpp, model: "large-v3", quantization: "q5_0",
                            errorRate: 0.06, timesRealtime: 6),
        ]
        let ranked = Ranking.rank(records, profile: .accurate)
        #expect(ranked.map(\.record.model) == ["large-v3-turbo", "large-v3", "small"])
        #expect(ranked.map(\.rank) == [1, 2, 3])
    }

    @Test func `Degenerate single-candidate set still ranks`() {
        let ranked = Ranking.rank([Fixtures.record()], profile: .balanced)
        #expect(ranked.count == 1)
        #expect(ranked[0].rank == 1)
    }
}

struct BenchmarkCacheTests {
    @Test func `Missing cache file loads as empty`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = BenchmarkCache(fileURL: dir.appendingPathComponent("benchmarks.json"))
        #expect(try cache.load().isEmpty)
    }

    @Test func `Upsert persists and re-running replaces the record for the same key`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = BenchmarkCache(fileURL: dir.appendingPathComponent("benchmarks.json"))

        let first = Fixtures.record(errorRate: 0.10)
        try cache.upsert([first])
        #expect(try cache.load().count == 1)

        // Same key (backend|model|quant|language), newer measurement.
        let second = BenchmarkRecord(
            backend: first.backend, model: first.model, quantization: first.quantization,
            language: first.language, metricKind: first.metricKind,
            errorRate: 0.05, rtf: first.rtf, peakMemoryGB: first.peakMemoryGB,
            audioDuration: first.audioDuration,
            measuredAt: first.measuredAt.addingTimeInterval(3600),
            chip: first.chip, macosVersion: first.macosVersion, appVersion: first.appVersion
        )
        try cache.upsert([second])
        let records = try cache.load()
        #expect(records.count == 1)
        #expect(records[0].errorRate == 0.05)
        #expect(records[0].measuredAt > first.measuredAt)
    }

    @Test func `Different keys accumulate`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = BenchmarkCache(fileURL: dir.appendingPathComponent("benchmarks.json"))
        try cache.upsert([Fixtures.record(model: "tiny")])
        try cache.upsert([Fixtures.record(model: "small")])
        #expect(try cache.load().count == 2)
    }
}

// MARK: - ±context delta (task 4.1; spec benchmark: Measure the context-biasing delta)

struct ContextDeltaBenchmarkTests {
    /// Baseline mishears ("hello"), the context prompt fixes it ("hello world")
    /// against reference "hello world": WER 0.5 → 0.0, delta -0.5.
    static func biasedEngine() -> MockEngine {
        MockEngine(id: .whisperKit, available: true) { _, options in
            let text = options.prompt == nil ? "hello" : "hello world"
            return RawTranscription(
                segments: [.init(start: 0, end: 2, text: text)], language: "en", duration: 2)
        }
    }

    private let candidate = BenchmarkCandidate(
        backend: .whisperKit, model: "tiny", quantization: "default")
    private let audio = AudioInfo(
        path: "clip.wav", duration: 60, format: "wav", sampleRate: 16000, channels: 1)

    @Test func `Context prompt adds a with-context pass and the delta per candidate`() async {
        let runner = BenchmarkRunner(
            engines: [Self.biasedEngine()], host: Fixtures.m5Max,
            probe: FakeClock(step: 1).probe())
        let outcome = await runner.run(
            candidates: [candidate], notes: [], audio: audio,
            referenceText: "hello world", metricKind: .wer, language: "en",
            contextPrompt: "鄭澈, world"
        )
        let measured = try! #require(outcome.measured.first)
        #expect(measured.record.errorRate == 0.5)       // baseline pass, persisted
        #expect(measured.contextErrorRate == 0.0)        // with-context pass
    }

    @Test func `Report gains ctx and delta columns and cache stays baseline-only`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ctxDir = dir.appendingPathComponent("ctx")
        try FileManager.default.createDirectory(at: ctxDir, withIntermediateDirectories: true)
        try #"{"version":1,"terms":["world"]}"#.write(
            to: ctxDir.appendingPathComponent("context.json"), atomically: true, encoding: .utf8)
        let audioPath = try makeWavFile(in: dir, seconds: 2.0)
        let srt = dir.appendingPathComponent("truth.srt").path
        try "1\n00:00:00,000 --> 00:00:02,000\nhello world\n".write(
            toFile: srt, atomically: true, encoding: .utf8)
        let store = BenchmarkStore(directory: dir.appendingPathComponent("store"))
        let core = CommandCore(
            engines: [Self.biasedEngine()],
            detect: { Fixtures.m5Max },
            store: store,
            probe: FakeClock(step: 1).probe()
        )

        let report = try await core.benchmark(
            audioPath: audioPath, referencePath: srt, language: "en",
            backendFilter: nil, modelFilter: ["tiny"], profileName: "balanced",
            asJSON: false, contextDir: ctxDir.path
        )
        #expect(report.contains("WER(CTX)%"))
        #expect(report.contains("DELTA"))
        #expect(report.contains("-50.0"))  // 0.5 → 0.0 in percent

        // Measurement rows carry the baseline error rate; the with-context
        // pass lands in context_error_rate (BCNF row, spec benchmark-store) —
        // the routing projection stays context-neutral.
        let rows = try store.load().measurements
        #expect(rows.count == 1)
        #expect(rows[0].errorRate == 0.5)
        #expect(rows[0].contextErrorRate == 0.0)

        // JSON mode carries the machine-readable fields.
        let json = try await core.benchmark(
            audioPath: audioPath, referencePath: srt, language: "en",
            backendFilter: nil, modelFilter: ["tiny"], profileName: "balanced",
            asJSON: true, contextDir: ctxDir.path
        )
        let doc = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let results = try #require(doc["results"] as? [[String: Any]])
        #expect(results[0]["context_error_rate"] as? Double == 0.0)
        #expect(results[0]["delta"] as? Double == -0.5)
    }

    @Test func `No context directory means single-pass runs and an unchanged report shape`() async {
        let runner = BenchmarkRunner(
            engines: [Self.biasedEngine()], host: Fixtures.m5Max,
            probe: FakeClock(step: 1).probe())
        let outcome = await runner.run(
            candidates: [candidate], notes: [], audio: audio,
            referenceText: "hello world", metricKind: .wer, language: "en"
        )
        #expect(outcome.measured.first?.contextErrorRate == nil)
        let report = BenchmarkReport.table(outcome: outcome, profile: .balanced)
        #expect(!report.contains("(CTX)%"))
        #expect(!report.contains("DELTA"))
    }
}
