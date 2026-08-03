import Foundation
import Testing
@testable import BestASRKit

/// CommandCore with everything injected: mock engines, fixed host, temp store,
/// deterministic clock. No real backend, no real detection, no network.
private func makeCore(
    engines: [any Engine],
    cacheDir: URL,
    host: SystemInfo = Fixtures.m5Max,
    languageDetector: (any AudioLanguageDetecting)? = nil
) -> CommandCore {
    CommandCore(
        engines: engines,
        detect: { host },
        store: BenchmarkStore(directory: cacheDir.appendingPathComponent("store")),
        probe: FakeClockProbe.probe(),
        languageDetector: languageDetector ?? StubLanguageDetector(language: "en")
    )
}

/// Language detection defaults to `WhisperKitLanguageDetector`, which downloads
/// and runs a real model. Leaving it in place made these tests depend on a
/// cached WhisperKit and a network — passing on a developer machine and failing
/// in CI, where the miss surfaces as a `--language auto` warning on every run.
/// Stubbing it keeps the suite hermetic, per the file's own contract.
private struct StubLanguageDetector: AudioLanguageDetecting {
    let language: String
    func detectLanguage(audioPath: String) async throws -> String { language }
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

    @Test func `an unavailable requested backend surfaces a warning off the explanation`()
        async throws
    {
        // #136: every router warning was folded into `explanation`, which the
        // CLI prints ONLY under --explain. So a user who asked for one backend
        // and silently received another's output saw nothing at all. Measured
        // during #121: `--backend apple-speech` wrote mlx-audio Whisper output
        // under the user's chosen name, with `Wrote txt transcript to …` as the
        // entire output.
        //
        // Warnings must therefore be reachable WITHOUT parsing the prose block,
        // so the CLI can print them on the default path.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let core = makeCore(engines: [MockEngine.fixed(.whisperKit)], cacheDir: dir)

        let request = SelectionRequest(
            profileName: "auto", backendOverride: "fluid-parakeet",  // not among the mock's engines
            modelOverride: nil, requestedLanguage: nil)
        let outcome = try await core.transcribe(
            audioPath: audio, selection: request, formatName: "txt", outputPath: nil)

        #expect(!outcome.warnings.isEmpty, "the substitution produced no structured warning")
        #expect(outcome.warnings.contains { $0.contains("fluid-parakeet") })
        #expect(outcome.warnings.contains { $0.contains("unavailable") })
        // The explanation keeps carrying them too — --explain output is unchanged.
        #expect(outcome.explanation.contains("fluid-parakeet"))
    }

    @Test func `a clean run carries no warnings, so the default path stays quiet`()
        async throws
    {
        // The other half of the contract: warnings print unconditionally, so an
        // ordinary run must not produce any, or the new output becomes noise
        // that trains the reader to ignore it.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let core = makeCore(engines: [MockEngine.fixed(.whisperKit)], cacheDir: dir)

        let outcome = try await core.transcribe(
            audioPath: audio, selection: auto, formatName: "txt", outputPath: nil)
        #expect(outcome.warnings.isEmpty, "clean run emitted: \(outcome.warnings)")
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

    @Test func `Production wiring bundles every non-external engine`() {
        // #35/#51 (spec asr-engine + external-engine-protocol): live() always
        // carries the bundled engines; external backends join only when the
        // user registry enables them, so this machine-dependent tail is
        // asserted by capability, not by exact list.
        // #121: apple-speech is bundled too — registered unconditionally, with
        // its own isAvailable() (not this list) gating pre-macOS-26 hosts.
        let ids = CommandCore.live().engines.map(\.id)
        #expect(ids.prefix(6) == [
            .whisperKit, .whisperCpp, .fluidParakeet, .fluidParaformer, .fluidSenseVoice,
            .appleSpeech,
        ])
        for extra in ids.dropFirst(6) {
            #expect(ExternalEngineRegistry.externalCapable.contains(extra))
        }
    }

    @Test func `list-models shows the live parakeet row alongside whisper sizes`() throws {
        // #35 (spec model-grid "Full-family catalog"): the live fluid-parakeet
        // row is a first-class catalog entry, not a reference footnote.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let core = makeCore(engines: [], cacheDir: dir)
        let output = core.listModels()
        #expect(output.contains("0.6b-v3"))
        #expect(output.contains("fluid-parakeet"))
    }

    @Test func `list-models shows the apple-speech row like every other live family`() throws {
        // #121: the catalog command's live section is documented as "every
        // bundled non-whisper backend renders its own rows". A grid row the
        // catalog never prints is undiscoverable — the user cannot learn that
        // `--backends apple-speech` exists, or that the row is unverified.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let core = makeCore(engines: [], cacheDir: dir)
        let output = core.listModels()
        #expect(output.contains("apple-speech"))
        #expect(output.contains("system"))
        // Unverified rows must say so, exactly as fluid-paraformer's does.
        let line = output.split(separator: "\n").first { $0.contains("apple-speech") }
        #expect(line?.contains("unverified") == true)
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

/// The #136 contract at the two layers the original fix left uncovered: which
/// notices the router classifies as warnings, and whether the CLI's rendering
/// of them actually reaches stderr.
struct RouterWarningVisibilityTests {

    /// Capture what `emit` writes, by handing it a real `FILE*` on a temp file.
    ///
    /// Deliberately NOT `dup2` on the process's fd 2, which is the more direct
    /// way to prove the destination and is unsafe inside a test bundle: after
    /// `close(2)` the next `open()` anywhere in the process receives fd 2, and
    /// restoring it then closes that resource out from under whoever opened it
    /// — including the harness's own result channel, which hangs the run. The
    /// default-destination assertion below covers what this cannot.
    private func captured(_ body: (UnsafeMutablePointer<FILE>) -> Void) throws -> String {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idd136-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard let f = fopen(path, "w") else { throw CocoaError(.fileWriteUnknown) }
        body(f)
        fclose(f)
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    // MARK: - classification (verify F1)

    @Test func `the unverified-model notice is a warning, not a reason`() throws {
        // Issue #136 names this notice explicitly among the warnings that "were
        // written to be seen. None is, by default." The first fix separated the
        // CLI's rendering but left this one in `reason`, so it stayed
        // --explain-only while the CHANGELOG said it had been unhidden.
        //
        // The tell was in the string itself: it began with the token "warning: "
        // while living in the reasons array — the exact reason/warning
        // conflation #136 exists to end, one layer below the one it fixed.
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "zh",
            backendOverride: "fluid-paraformer", modelOverride: nil,
            records: [], availability: [.fluidParaformer: true]
        )
        #expect(rec.backend == .fluidParaformer)
        #expect(
            rec.warnings.contains { $0.contains("unverified") },
            "the #50 notice is not in warnings: \(rec.warnings)")
        #expect(
            !rec.reason.contains { $0.contains("unverified") },
            "the #50 notice is still duplicated into reasons: \(rec.reason)")
    }

    @Test func `the unverified-model warning is not double-prefixed`() throws {
        // The CLI adds its own "warning: " prefix, so a straight move of the
        // string would render `warning: warning: '…' is unverified`.
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "zh",
            backendOverride: "fluid-paraformer", modelOverride: nil,
            records: [], availability: [.fluidParaformer: true]
        )
        let notice = try #require(rec.warnings.first { $0.contains("unverified") })
        #expect(!notice.lowercased().hasPrefix("warning:"), "double prefix: \(notice)")
    }

    // MARK: - rendering (verify F2)

    // The original fix asserted only that `TranscribeOutcome.warnings` was
    // populated — the data was reachable, which is necessary and is not the
    // acceptance criterion. Deleting the CLI's entire printing branch left all
    // 447 tests green, reproducing one layer up the exact failure mode the
    // issue's third acceptance line names.
    //
    // Three properties have to hold, and no single assertion covers them:
    // which lines (branch), how they read (prefix), and WHERE they go. The
    // last one is why `destination` is a named constant rather than an inlined
    // `stderr` — a pure test of the rendered strings stays green when they are
    // sent to stdout, which for anyone piping a transcript is #136 again.

    @Test func `the default path renders each warning with a prefix`() throws {
        let outcome = TranscribeOutcome(
            outputPath: "/tmp/x.txt", format: "txt", explanation: "Selected … because:",
            warnings: ["a", "b"])
        #expect(
            TranscribeDiagnostics.lines(for: outcome, explain: false) == ["warning: a", "warning: b"]
        )
    }

    @Test func `--explain renders the explanation and never duplicates warnings`() throws {
        let outcome = TranscribeOutcome(
            outputPath: "/tmp/x.txt", format: "txt", explanation: "Selected … because:\n  ! a",
            warnings: ["a"])
        let lines = TranscribeDiagnostics.lines(for: outcome, explain: true)
        #expect(lines == ["Selected … because:\n  ! a"])
        #expect(!lines.contains { $0.hasPrefix("warning:") })
    }

    @Test func `a clean run renders nothing at all`() throws {
        let outcome = TranscribeOutcome(
            outputPath: "/tmp/x.txt", format: "txt", explanation: "", warnings: [])
        #expect(TranscribeDiagnostics.lines(for: outcome, explain: false).isEmpty)
    }

    @Test func `diagnostics go to stderr, never stdout`() throws {
        // The destination assertion. Flipping this constant to `stdout` is a
        // one-word change that every string-level test above tolerates.
        #expect(TranscribeDiagnostics.destination == stderr)
        #expect(TranscribeDiagnostics.destination != stdout)
    }

    @Test func `emit writes the rendered lines to the stream it is given`() throws {
        let outcome = TranscribeOutcome(
            outputPath: "/tmp/x.txt", format: "txt", explanation: "", warnings: ["substituted"])
        let text = try captured { TranscribeDiagnostics.emit(for: outcome, explain: false, to: $0) }
        #expect(text == "warning: substituted\n", "got: \(text)")
    }

    @Test func `emitting nothing writes nothing`() throws {
        let outcome = TranscribeOutcome(
            outputPath: "/tmp/x.txt", format: "txt", explanation: "", warnings: [])
        let text = try captured { TranscribeDiagnostics.emit(for: outcome, explain: false, to: $0) }
        #expect(text.isEmpty, "a clean run wrote: \(text)")
    }

    @Test func `an unwritable stream does not raise, unlike the old FileHandle API`() throws {
        // `FileHandle.write(_:)` raises an uncatchable ObjC exception on write
        // failure, so a closed fd 2 (`2>&-`) turned a completed transcription
        // into SIGABRT — file already on disk, "Wrote …" already printed, exit
        // code 134. An early-exiting stderr reader gave SIGPIPE the same way.
        // Pre-existing API misuse, promoted from --explain-only to the default
        // path by the #136 fix, and reached through the templates in
        // plugins/bestasr/skills/ that gate on `$?`.
        //
        // A read-only stream reproduces the EBADF-class failure without
        // touching the process's own descriptors. Scoped deliberately: this
        // covers the uncatchable-exception class, NOT SIGPIPE — that is a
        // signal from the underlying write and no choice of stdio API
        // suppresses it, so an early-exiting reader can still take the process
        // down. The test name used to claim the wider property.
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idd136-ro-\(UUID().uuidString)").path
        FileManager.default.createFile(atPath: path, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: path) }
        let ro = try #require(fopen(path, "r"))
        defer { fclose(ro) }
        let outcome = TranscribeOutcome(
            outputPath: "/tmp/x.txt", format: "txt", explanation: "", warnings: ["x"])
        TranscribeDiagnostics.emit(for: outcome, explain: false, to: ro)  // must not trap
    }
}

/// Link 6: that the CLI still *invokes* the tested rendering, unguarded, in the
/// right order.
///
/// The rest of the #136 suite covers which lines are produced, how they read,
/// and where `emit` writes. None of that observes whether
/// `Sources/bestasr/BestASRCommand.swift` calls any of it — and #136 was a
/// wiring bug, not a rendering bug: the reported behaviour is an `if explain`
/// guard at the call site. Measured before this test existed: re-adding that
/// guard, deleting the call, redirecting it to stdout, or moving it after the
/// success line each left **456/456 green**.
///
/// Why a source-level lock rather than executing the command: `Transcribe.run()`
/// calls `CommandCore.live()` unconditionally, which hard-codes six engines plus
/// `ExternalEngineRegistry`. There is no injection seam, and `$HOME` is not one
/// either — `NSHomeDirectory()` ignores it on Darwin, so a subprocess test aimed
/// at a fake home silently loads the developer's real `~/.bestasr/engines.json`
/// and can spawn a real model. A subprocess CLI test on this path is
/// non-hermetic by construction today; building the seam that would fix that is
/// a larger and more debatable change than the gap it closes.
struct TranscribeDiagnosticsWiringTests {

    @Test func `the CLI reports through the tested path, unguarded and before nothing else`()
        throws
    {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/bestasr/BestASRCommand.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        // Strip comments and all whitespace so reflowing the call or inserting a
        // comment between statements stays green — those are refactors, not
        // regressions. (Safe here: this file contains no `://` inside a string
        // literal, which is the one shape this stripping would mangle.)
        let stripped = source
            .components(separatedBy: "\n")
            .map { line -> String in
                guard let r = line.range(of: "//") else { return line }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined()
            .filter { !$0.isWhitespace }

        #expect(
            stripped.contains("TranscribeDiagnostics.report(result,explain:explain)"),
            """
            The transcribe command no longer reports through TranscribeDiagnostics.report \
            with no stream override. If that was deliberate — the call was renamed, \
            restructured, or moved — re-pin this assertion to the new shape. If it was not, \
            #136 is back: warnings stop reaching stderr on the default path and every other \
            test in this suite stays green.
            """)

        // The guard that IS the reported bug. `report` is unconditional; making
        // it conditional on `explain` restores #136 byte-for-byte.
        #expect(
            !stripped.contains("ifexplain{TranscribeDiagnostics"),
            "the diagnostics call is guarded by `explain` again — that is #136 verbatim")
    }
}

/// `report` puts both streams under test at once, which is the only place the
/// success line gets any assertion at all.
struct TranscribeReportTests {

    private func capture(
        _ body: (UnsafeMutablePointer<FILE>, UnsafeMutablePointer<FILE>) -> Void
    ) throws -> (out: String, err: String) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idd136-rep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let op = dir.appendingPathComponent("out").path
        let ep = dir.appendingPathComponent("err").path
        guard let fo = fopen(op, "w"), let fe = fopen(ep, "w") else {
            throw CocoaError(.fileWriteUnknown)
        }
        body(fo, fe)
        fclose(fo)
        fclose(fe)
        // Read before the defer removes the directory; `String(contentsOfFile:)`
        // throwing would otherwise be indistinguishable from "wrote nothing".
        let out = try String(contentsOfFile: op, encoding: .utf8)
        let err = try String(contentsOfFile: ep, encoding: .utf8)
        return (out, err)
    }

    @Test func `warnings go to stderr and the success line to stdout, warnings first`() throws {
        let outcome = TranscribeOutcome(
            outputPath: "/tmp/x.srt", format: "srt", explanation: "", warnings: ["substituted"])
        let io = try capture { TranscribeDiagnostics.report(outcome, explain: false, out: $0, err: $1) }
        #expect(io.err == "warning: substituted\n")
        #expect(io.out == "Wrote srt transcript to /tmp/x.srt\n")
        // Ordering is a property of `report`, so it is asserted where it lives
        // rather than inferred from two adjacent statements at the call site.
        #expect(!io.out.contains("warning:"), "a warning leaked onto stdout")
    }

    @Test func `the warning precedes the success line when both share a stream`() throws {
        // Ordering is only observable when the two land in the same place, which
        // is the `2>&1` case the claim is about. Captured separately it is
        // invisible — two files have no relative order — so this is the one
        // assertion that can fail if `report` is reordered.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idd136-ord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("merged").path
        let merged = try #require(fopen(path, "w"))
        let outcome = TranscribeOutcome(
            outputPath: "/tmp/x.srt", format: "srt", explanation: "", warnings: ["substituted"])
        TranscribeDiagnostics.report(outcome, explain: false, out: merged, err: merged)
        fclose(merged)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let w = try #require(text.range(of: "warning: substituted"))
        let s = try #require(text.range(of: "Wrote srt transcript"))
        #expect(w.lowerBound < s.lowerBound, "the success line came first: \(text)")
    }

    @Test func `an embedded NUL neither truncates a warning nor glues the next one to it`() throws {
        // `fputs` stops at the first NUL and drops the newline with it, so two
        // warnings arrived as one physical line with the tail of the first
        // missing. `TranscribeOutcome` is public, so this is reachable by a
        // library caller even though argv cannot carry a NUL.
        let outcome = TranscribeOutcome(
            outputPath: "/tmp/x.txt", format: "txt", explanation: "",
            warnings: ["abc\u{0}def", "second"])
        let io = try capture { TranscribeDiagnostics.report(outcome, explain: false, out: $0, err: $1) }
        #expect(io.err.contains("def"), "the warning was truncated at the NUL: \(io.err)")
        #expect(
            io.err.components(separatedBy: "\n").filter { $0.hasPrefix("warning:") }.count == 2,
            "the two warnings were glued into one line: \(io.err)")
    }

    @Test func `a clean run still announces the transcript`() throws {
        let outcome = TranscribeOutcome(
            outputPath: "/tmp/x.txt", format: "txt", explanation: "", warnings: [])
        let io = try capture { TranscribeDiagnostics.report(outcome, explain: false, out: $0, err: $1) }
        #expect(io.err.isEmpty, "a clean run wrote to stderr: \(io.err)")
        #expect(io.out == "Wrote txt transcript to /tmp/x.txt\n")
    }
}
