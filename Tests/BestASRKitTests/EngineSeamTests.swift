import Foundation
import Testing

@testable import BestASRKit

/// The convergence condition round 8's verify asked for (#183).
///
/// Four rounds fixed four instances of one defect: a producer changed and a
/// consumer did not. Round 7 broke `transcribe`; round 8 fixed `transcribe`
/// and left `benchmark` carrying the identical break, in the same commit. Each
/// time the two measured paths were checked — when checked at all — by
/// different assertions, so agreeing was never required of them.
///
/// This file exists to make that impossible: ONE predicate, called from both
/// paths. A change that satisfies it on one path and abandons it on the other
/// fails here regardless of which path was edited.
enum EngineSeam {

    /// What every measured path must hand an engine.
    ///
    /// Not "a string that happens to work today" — a string this runtime can
    /// resolve to exactly one model, spelled the one way the catalog spells
    /// it. A bare size satisfies neither half under a runtime that publishes
    /// two families at that size, which is the ambiguity #183 exists to end.
    static func expectCanonical(_ spy: OptionsSpy, backend: BackendID, path: String) {
        let models = spy.models
        // Non-vacuity: an empty observation list satisfies every `allSatisfy`
        // below, and a path that never reached its engine would then read as
        // a path that reached it correctly.
        #expect(!models.isEmpty, "\(path): the engine was never called, so nothing was checked")

        for model in models {
            switch ModelGrid.identity(backend: backend.rawValue, matching: model) {
            case .resolved(let identity):
                let canonical = ModelGrid.address(for: identity)
                #expect(
                    model == canonical,
                    "\(path): engine received '\(model)', not the canonical '\(canonical)'")
            case .ambiguous(let candidates):
                Issue.record(
                    """
                    \(path): engine received '\(model)', which names \(candidates.count) \
                    models under \(backend.rawValue) — so it names none of them
                    """)
            case .unknown:
                Issue.record(
                    """
                    \(path): engine received '\(model)', which \(backend.rawValue) \
                    cannot place in the catalog
                    """)
            }
        }
    }
}

/// Task: the address reaches the engine intact on BOTH measured paths.
struct EngineSeamTests {

    @Test func `the transcribe path hands the engine a canonical address`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let spy = OptionsSpy()
        let core = CommandCore(
            engines: [MockEngine.spying(.whisperKit, into: spy)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            probe: FakeClockProbe.probe()
        )

        _ = try await core.transcribe(
            audioPath: audio,
            selection: SelectionRequest(
                profileName: "high", backendOverride: "whisperkit", modelOverride: nil,
                requestedLanguage: "en"),
            formatName: "txt", outputPath: nil)

        EngineSeam.expectCanonical(spy, backend: .whisperKit, path: "transcribe")
    }

    @Test func `the benchmark path hands the engine a canonical address`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir, seconds: 2.0)
        let srt = dir.appendingPathComponent("truth.srt").path
        try "1\n00:00:00,000 --> 00:00:02,000\nhello world\n".write(
            toFile: srt, atomically: true, encoding: .utf8)
        let spy = OptionsSpy()
        let core = CommandCore(
            engines: [MockEngine.spying(.whisperKit, into: spy)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            probe: FakeClockProbe.probe()
        )

        _ = try await core.benchmark(
            audioPath: audio, referencePath: srt, language: "en",
            backendFilter: ["whisperkit"], modelFilter: nil, profileName: "medium", asJSON: false)

        EngineSeam.expectCanonical(spy, backend: .whisperKit, path: "benchmark")
    }

    @Test func `the benchmark path persists a key the catalog can place`() async throws {
        // The other end of the same run. Reaching the engine correctly is half
        // the claim; what gets WRITTEN is the half that outlives the process,
        // and it is where the lost revision pin came from — a record without
        // an identity keyed itself `whisperkit|whisper|whisper/large-v3-turbo`,
        // a family and a size that were never those things.
        //
        // Dropping the identity the runner carries passes every other test in
        // this suite. It does not pass this one.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir, seconds: 2.0)
        let srt = dir.appendingPathComponent("truth.srt").path
        try "1\n00:00:00,000 --> 00:00:02,000\nhello world\n".write(
            toFile: srt, atomically: true, encoding: .utf8)
        let store = BenchmarkStore(directory: dir.appendingPathComponent("store"))
        let core = CommandCore(
            engines: [MockEngine.fixed(.whisperKit)],
            detect: { Fixtures.m5Max }, store: store, probe: FakeClockProbe.probe())

        _ = try await core.benchmark(
            audioPath: audio, referencePath: srt, language: "en",
            backendFilter: ["whisperkit"], modelFilter: nil, profileName: "medium", asJSON: false)

        let written = try store.load().measurements
        #expect(!written.isEmpty, "nothing was persisted, so nothing was checked")
        for row in written {
            let parts = row.modelId.split(separator: "|", omittingEmptySubsequences: false)
            #expect(parts.count == 4, "not a four-segment key: \(row.modelId)")
            // The key's own segments must name a model this catalog holds —
            // which a mangled key does not, however well-formed it looks.
            #expect(
                ModelGrid.rows.contains { $0.modelId == row.modelId },
                "persisted '\(row.modelId)', which is not a catalog row")
        }
    }

    @Test func `an explicit model override still arrives canonical`() async throws {
        // The path a user drives directly: `--model tiny` names one model under
        // whisperkit, and what reaches the engine is that model's address.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let spy = OptionsSpy()
        let core = CommandCore(
            engines: [MockEngine.spying(.whisperKit, into: spy)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            probe: FakeClockProbe.probe()
        )

        _ = try await core.transcribe(
            audioPath: audio,
            selection: SelectionRequest(
                profileName: "high", backendOverride: "whisperkit", modelOverride: "tiny",
                requestedLanguage: "en"),
            formatName: "txt", outputPath: nil)

        EngineSeam.expectCanonical(spy, backend: .whisperKit, path: "transcribe --model tiny")
        #expect(spy.models.allSatisfy { $0 == "whisper/tiny" })
    }
}

/// The other half of the seam: each runtime translates the address into its
/// OWN vocabulary, at the one place that cannot be skipped — the place that
/// loads the model.
///
/// Round 8 put this translation at the caller instead, where installing it is
/// optional and forgetting it is silent. Here an engine that fails to
/// translate cannot load anything, and these tests say so directly.
struct EngineVocabularyTests {

    @Test func `every backend states how its runtime spells a model`() {
        // A closed enumeration, asserted closed. A backend missing from the
        // table would fall back to passing the address through — which is
        // right for an unknown external adapter and wrong for one of ours,
        // and nothing in the type would say which.
        for backend in BackendID.allCases {
            #expect(
                ModelGrid.engineVocabularies[backend.rawValue] != nil,
                "\(backend.rawValue) does not say how its runtime spells a model")
        }
        for backend in Set(ModelGrid.rows.map(\.backend)) {
            #expect(
                ModelGrid.engineVocabularies[backend] != nil,
                "catalog backend \(backend) does not say how its runtime spells a model")
        }
    }

    @Test func `a size-vocabulary runtime receives the bare size`() {
        #expect(
            ModelGrid.engineName(backend: ModelGrid.backendWhisperKit,
                                 address: "whisper/large-v3-turbo") == "large-v3-turbo")
        #expect(
            ModelGrid.engineName(backend: ModelGrid.backendWhisperCpp,
                                 address: "whisper/tiny") == "tiny")
    }

    @Test func `an address-vocabulary runtime keeps the family`() {
        // mlx-audio publishes canary 1b and mms 1b. The bare size names
        // neither, so its own vocabulary IS the address — and a translation
        // rule that dropped the family here would hand one model's name to the
        // other's pin. Round 8 shipped exactly that rule.
        #expect(
            ModelGrid.engineName(backend: ModelGrid.backendMLXAudio,
                                 address: "canary/1b") == "canary/1b")
        #expect(
            ModelGrid.engineName(backend: ModelGrid.backendMLXAudio,
                                 address: "mms/1b") == "mms/1b")
    }

    @Test func `a string the catalog cannot place passes through untouched`() {
        // An external adapter's own vocabulary is not ours to rewrite, and
        // inventing a translation for it would be guessing.
        #expect(
            ModelGrid.engineName(backend: ModelGrid.backendWhisperKit,
                                 address: "some-fork/experimental") == "some-fork/experimental")
    }

    @Test func `WhisperKit resolves the address to its own catalog name`() {
        // WhisperKit's catalog spells it with an underscore; the address never
        // does. This is the translation whose absence broke `transcribe`.
        #expect(WhisperKitEngine.whisperKitModelName(for: "whisper/large-v3-turbo")
                == "large-v3_turbo")
        #expect(WhisperKitEngine.whisperKitModelName(for: "whisper/small") == "small")
    }

    @Test func `whisper.cpp resolves the address to its own file name`() {
        #expect(WhisperCppEngine.modelFileName(model: "whisper/tiny", quantization: "q5_1")
                == "ggml-tiny-q5_1.bin")
    }

    @Test func `the parakeet version table is keyed by what the address resolves to`() {
        // `modelVersions` is keyed by size. Handing it the address would miss,
        // and the engine would refuse to load a model it does support.
        let name = ModelGrid.engineName(
            backend: ModelGrid.backendFluidParakeet, address: "parakeet/0.6b-v3")
        #expect(ParakeetEngine.modelVersions[name] != nil,
                "'\(name)' is not a key of the version table")
    }
}
