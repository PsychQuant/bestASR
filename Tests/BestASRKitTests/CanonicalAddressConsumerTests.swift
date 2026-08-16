import Foundation
import Testing

@testable import BestASRKit

/// Round-7 CRITICALs (#183). `StoreProjection` emits the canonical address
/// `family/size`; four consumers still parsed a bare size, and every test that
/// guarded them built its fixture in the PRE-change shape, so 546 tests stayed
/// green while the measured path broke.
///
/// Every fixture here is the string the projection actually produces.
struct CanonicalAddressConsumerTests {

    /// The #105 declared-language gate. A parakeet row lists European
    /// languages only; it must never win a zh request.
    @Test func `The declared-language gate still fires on a canonical address`() {
        // Pre-change shape — what the old tests used, and why they passed.
        #expect(!Router.declaredSupport(
            backend: "fluid-parakeet", model: "0.6b-v3", language: "zh"))
        // Post-change shape — what the projection now emits. `$0.size == model`
        // matched nothing here, so the guard returned true and let a
        // European-only row rank for zh.
        #expect(!Router.declaredSupport(
            backend: "fluid-parakeet", model: "parakeet/0.6b-v3", language: "zh"))
        #expect(Router.declaredSupport(
            backend: "fluid-parakeet", model: "parakeet/0.6b-v3", language: "en"))
    }

    /// `--model tiny` must still reach the 41 stored whisperkit measurements.
    @Test func `A typed model name matches a measured record's canonical address`() throws {
        let identity = try #require(ModelID(family: "whisper", size: "tiny"))
        let record = BenchmarkRecord(
            backend: "whisperkit", model: ModelGrid.address(for: identity),
            quantization: Quantization.deferred(.runtime).serialised,
            identity: identity, language: "en", metricKind: .wer,
            errorRate: 0.05, rtf: 0.05, peakMemoryGB: 1, audioDuration: 10,
            measuredAt: Date(timeIntervalSince1970: 1), chip: "Apple M5 Max",
            macosVersion: "27.0", appVersion: "0.3.0")

        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .medium, requestedLanguage: "en",
            backendOverride: "whisperkit", modelOverride: "tiny",
            records: [record], availability: [.whisperKit: true])
        // Measured, not cold-start: the override matched the stored record.
        #expect(rec.dataSource == .measured,
                "--model tiny no longer reaches measured history; reasons: \(rec.reason)")
    }

    /// The engine boundary. A vendor API wants its own name, not our address.
    @Test func `The engine receives the vendor's own model name`() throws {
        let identity = try #require(ModelID(family: "whisper", size: "large-v3-turbo"))
        #expect(ModelGrid.address(for: identity) == "whisper/large-v3-turbo")
        // WhisperKit's own catalog calls it `large-v3-turbo`. Handing it the
        // address would fail to load.
        #expect(ModelGrid.engineName(
            backend: ModelGrid.backendWhisperKit,
            address: ModelGrid.address(for: identity)) == "large-v3-turbo")
    }

    /// `--models` must accept what a user can see, in either spelling.
    @Test func `The benchmark model filter accepts both spellings`() async throws {
        let runner = BenchmarkRunner(
            engines: [MockEngine.fixed(.whisperKit)], host: Fixtures.m5Max)
        for spelling in ["large-v3-turbo", "whisper/large-v3-turbo"] {
            let enumeration = try await runner.enumerateCandidates(
                backendFilter: ["whisperkit"], modelFilter: [spelling])
            #expect(enumeration.candidates.count == 1,
                    "--models \(spelling) enumerated \(enumeration.candidates.count)")
        }
    }
}

/// The engine boundary, after round 8's verify moved it.
///
/// The translation used to live at the CALLER (`CommandCore.engineModelName`),
/// where installing it was optional — and it was installed at one of its two
/// call sites, leaving `benchmark` broken by the commit that fixed
/// `transcribe`. It now lives inside each engine, at the point that loads the
/// model, so an engine that skips it cannot load anything.
///
/// These tests moved with it; the round-trip claim below is unchanged and now
/// covers the case the old rule got wrong.
struct EngineBoundaryTranslationTests {
    @Test func `Each engine translates the address into its own vocabulary`() throws {
        #expect(WhisperKitEngine.whisperKitModelName(for: "whisper/large-v3-turbo")
                == "large-v3_turbo")
        #expect(WhisperCppEngine.modelFileName(model: "whisper/tiny", quantization: "q5_1")
                == "ggml-tiny-q5_1.bin")
        #expect(ModelGrid.engineName(
            backend: ModelGrid.backendFluidParakeet, address: "parakeet/0.6b-v3") == "0.6b-v3")
        // A name the runtime already uses is unchanged.
        #expect(ModelGrid.engineName(
            backend: ModelGrid.backendWhisperKit, address: "tiny") == "tiny")
        // A string the catalog cannot place passes through rather than being
        // guessed at — an external adapter may have its own vocabulary.
        #expect(ModelGrid.engineName(
            backend: ModelGrid.backendWhisperKit, address: "who/knows") == "who/knows")
    }

    @Test func `The translation is not lossy — the address resolves back`() throws {
        for row in ModelGrid.rows {
            let address = ModelGrid.address(for: row.identity)
            #expect(ModelGrid.identity(backend: row.backend, matching: address)
                    == .resolved(row.identity))
            // What the runtime is handed is what that runtime calls the model
            // — which is NOT `row.size` everywhere. Round 8 asserted exactly
            // that here, and the assertion passed because no case in the loop
            // contradicted a rule the catalog itself does.
            let expected: String
            switch ModelGrid.engineVocabularies[row.backend] {
            case .size: expected = row.size
            case .address: expected = address
            case nil:
                Issue.record("\(row.backend) does not say how its runtime spells a model")
                continue
            }
            #expect(ModelGrid.engineName(backend: row.backend, address: address) == expected,
                    "\(row.modelId): wrong vocabulary at the engine boundary")
        }
    }
}
