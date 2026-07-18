import Foundation
import Testing
@testable import BestASRKit

/// #105 — `--language auto` language-aware routing: the declared-language
/// gate, the parakeet catalog correction, and the auto-detection plumbing.
struct LanguageRoutingTests {
    // MARK: - Catalog correction

    @Test func `Parakeet rows no longer claim blanket multilingual support`() {
        let fluid = ModelGrid.rows(backend: "fluid-parakeet", priorityCeiling: nil)
        #expect(!fluid.isEmpty)
        for row in fluid {
            #expect(!row.languages.contains("multi"))
            for cjk in ["zh", "ja", "ko"] { #expect(!row.languages.contains(cjk)) }
            #expect(row.languages.contains("en"))
        }
        let mlxParakeet = ModelGrid.rows(backend: "mlx-audio", priorityCeiling: nil)
            .filter { $0.family == "parakeet" }
        #expect(!mlxParakeet.isEmpty)
        for row in mlxParakeet {
            #expect(!row.languages.contains("multi"))
            #expect(!row.languages.contains("zh"))
        }
    }

    // MARK: - Declared-language gate

    @Test func `Declared gate rejects parakeet for zh and accepts it for en`() {
        #expect(Router.declaredSupport(backend: "fluid-parakeet", model: "0.6b-v3", language: "en"))
        #expect(!Router.declaredSupport(backend: "fluid-parakeet", model: "0.6b-v3", language: "zh"))
        #expect(
            !Router.declaredSupport(backend: "fluid-parakeet", model: "0.6b-v3", language: "zh-TW"))
    }

    @Test func `Declared gate fails open for models outside the grid`() {
        #expect(Router.declaredSupport(backend: "whisperkit", model: "large-v3", language: "zh"))
    }

    @Test func `Router never ranks a zh request onto a backend whose row lacks zh`() throws {
        let host = SystemInfo(
            chip: "TestChip", unifiedMemoryGB: 64, hasANE: true, macosVersion: "26.0")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func record(_ backend: String, _ model: String, error: Double) -> BenchmarkRecord {
            BenchmarkRecord(
                backend: backend, model: model, quantization: "default", language: "zh",
                metricKind: .cer, errorRate: error, rtf: 0.1, peakMemoryGB: 1,
                audioDuration: 60, measuredAt: date, chip: "TestChip",
                macosVersion: "26.0", appVersion: "test")
        }
        // A (mislabeled) flattering parakeet zh row must lose to whisperkit zh.
        let rec = try Router.recommend(
            host: host, profile: .medium, requestedLanguage: "zh",
            backendOverride: nil, modelOverride: nil,
            records: [
                record("fluid-parakeet", "0.6b-v3", error: 0.01),
                record("whisperkit", "large-v3", error: 0.10),
            ],
            availability: [.whisperKit: true, .fluidParakeet: true])
        #expect(rec.backend == .whisperKit)
    }

    @Test func `An explicit backend lock bypasses the gate with a support warning`() throws {
        let host = SystemInfo(
            chip: "TestChip", unifiedMemoryGB: 64, hasANE: true, macosVersion: "26.0")
        let rec = try Router.recommend(
            host: host, profile: .medium, requestedLanguage: "zh",
            backendOverride: "fluid-parakeet", modelOverride: nil,
            records: [
                BenchmarkRecord(
                    backend: "fluid-parakeet", model: "0.6b-v3", quantization: "default",
                    language: "zh", metricKind: .cer, errorRate: 0.10, rtf: 0.1,
                    peakMemoryGB: 1, audioDuration: 60,
                    measuredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    chip: "TestChip", macosVersion: "26.0", appVersion: "test")
            ],
            availability: [.whisperKit: true, .fluidParakeet: true])
        // The user's will governs (quality-floor doctrine) — but never silently.
        #expect(rec.backend == .fluidParakeet)
        #expect(rec.dataSource == .measured)
        #expect(rec.warnings.contains { $0.contains("does not list support for language 'zh'") })
    }

    // MARK: - Auto-detection plumbing

    struct FakeDetector: AudioLanguageDetecting {
        let result: Result<String, any Error>
        func detectLanguage(audioPath: String) async throws -> String {
            try result.get()
        }
    }
    struct Boom: Error {}

    private func core(_ detector: FakeDetector) -> CommandCore {
        CommandCore(engines: [], languageDetector: detector)
    }

    @Test func `Auto resolves to the detected language with an explain reason`() async {
        let out = await core(FakeDetector(result: .success(" ZH "))).resolveAutoLanguage(
            audioPath: "/tmp/x.wav", resolved: nil)
        #expect(out.language == "zh")
        #expect(out.warnings.isEmpty)
        #expect(out.reasons.contains { $0.contains("detected language 'zh'") })
    }

    @Test func `Detection failure falls back to nil ranking with a warning`() async {
        let out = await core(FakeDetector(result: .failure(Boom()))).resolveAutoLanguage(
            audioPath: "/tmp/x.wav", resolved: nil)
        #expect(out.language == nil)
        #expect(out.reasons.isEmpty)
        #expect(out.warnings.contains { $0.contains("auto-detection unavailable") })
    }

    @Test func `An explicit language bypasses detection entirely`() async {
        let out = await core(FakeDetector(result: .failure(Boom()))).resolveAutoLanguage(
            audioPath: "/tmp/x.wav", resolved: "ja")
        #expect(out.language == "ja")
        #expect(out.reasons.isEmpty && out.warnings.isEmpty)
    }
}
