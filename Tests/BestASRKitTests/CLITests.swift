import Foundation
import Testing
@testable import BestASRKit

/// CommandCore with everything injected: mock engines, fixed host, temp cache,
/// deterministic clock. No real backend, no real detection, no network.
private func makeCore(
    engines: [any Engine],
    cacheDir: URL,
    host: SystemInfo = Fixtures.m5Max
) -> CommandCore {
    CommandCore(
        engines: engines,
        detect: { host },
        cache: BenchmarkCache(fileURL: cacheDir.appendingPathComponent("benchmarks.json")),
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
    profileName: "balanced", backendOverride: nil, modelOverride: nil, requestedLanguage: "auto")

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
        let cache = BenchmarkCache(fileURL: dir.appendingPathComponent("benchmarks.json"))
        try cache.upsert([Fixtures.record(language: "zh")])  // chip matches Fixtures.m5Max
        let core = CommandCore(
            engines: [MockEngine.fixed(.whisperKit)],
            detect: { Fixtures.m5Max },
            cache: cache,
            probe: FakeClockProbe.probe()
        )

        let selection = SelectionRequest(
            profileName: "accurate", backendOverride: nil, modelOverride: nil,
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
        let cache = BenchmarkCache(fileURL: dir.appendingPathComponent("benchmarks.json"))
        let core = CommandCore(
            engines: [MockEngine.fixed(.whisperKit)],
            detect: { Fixtures.m5Max },
            cache: cache,
            probe: FakeClockProbe.probe()
        )

        let report = try await core.benchmark(
            audioPath: audio, referencePath: srt, language: "en",
            backendFilter: nil, modelFilter: ["tiny"], profileName: "balanced", asJSON: false
        )
        #expect(report.contains("RANK"))
        #expect(report.contains("whisperkit"))
        #expect(try cache.load().count == 1)  // persisted (spec: benchmark command)
        #expect(try cache.load()[0].errorRate == 0)  // mock says exactly "hello world"
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
            backendFilter: nil, modelFilter: ["tiny"], profileName: "balanced", asJSON: true
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
                backendFilter: nil, modelFilter: nil, profileName: "balanced", asJSON: false
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
                backendFilter: nil, modelFilter: ["tiny"], profileName: "balanced", asJSON: false
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
        #expect(output.contains("q5_0"))
    }
}
