import Foundation
import Testing
@testable import BestASRKit

/// Chinese-family engine contract (#50, spec chinese-asr-engines): Paraformer
/// and SenseVoice conform to the same Engine seam as Parakeet (#35), but
/// their pipelines yield plain text — one full-duration segment, nil
/// confidence, no fabricated timings.
struct ChineseEnginesTests {
    let options = TranscribeOptions(model: "large-zh", quantization: "default", language: "zh")

    struct SpyPipeline: TextTranscribing {
        let result: @Sendable (String, String?) throws -> String

        func transcribe(audioPath: String, language: String?) async throws -> String {
            try result(audioPath, language)
        }
    }

    @Test func `Engines identify as their backends and are available`() async {
        #expect(ChineseFamilyEngine.paraformer().id == .fluidParaformer)
        #expect(ChineseFamilyEngine.sensevoice().id == .fluidSenseVoice)
        #expect(await ChineseFamilyEngine.paraformer().isAvailable() == true)
    }

    @Test func `Text-only output maps to a single full-duration segment`() async throws {
        let engine = ChineseFamilyEngine(
            id: .fluidParaformer,
            probeDuration: { _ in 30.0 },
            pipelineFactory: { _ in SpyPipeline { _, _ in "你好 世界" } })
        let raw = try await engine.transcribeRaw(audioPath: "talk.wav", options: options)
        try #require(raw.segments.count == 1)
        #expect(raw.segments[0].text == "你好 世界")
        #expect(raw.segments[0].start == 0)
        #expect(raw.segments[0].end == 30.0)
        #expect(raw.segments[0].confidence == nil)
        #expect(raw.duration == 30.0)
    }

    @Test func `Empty transcription yields no segments rather than an empty cue`() async throws {
        let engine = ChineseFamilyEngine(
            id: .fluidSenseVoice,
            probeDuration: { _ in 5.0 },
            pipelineFactory: { _ in SpyPipeline { _, _ in "  " } })
        let raw = try await engine.transcribeRaw(audioPath: "silence.wav", options: options)
        #expect(raw.segments.isEmpty)
    }

    @Test func `Factory failure surfaces as a typed TranscriptionError naming the backend`() async {
        struct DownloadFailed: Error, LocalizedError {
            var errorDescription: String? { "weights download failed" }
        }
        let engine = ChineseFamilyEngine(
            id: .fluidParaformer,
            probeDuration: { _ in 1.0 },
            pipelineFactory: { _ in throw DownloadFailed() })
        do {
            _ = try await engine.transcribeRaw(audioPath: "x.wav", options: options)
            Issue.record("expected throw")
        } catch let error as TranscriptionError {
            #expect(error.backend == "fluid-paraformer")
            #expect(error.message.contains("weights download failed"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func `Chinese-family live rows are listed in the grid`() {
        // spec model-grid (#50): both rows appear without a priority ceiling;
        // only sensevoice (priority 1, verified) enumerates by default.
        let all = ModelGrid.rows.filter {
            $0.backend == ModelGrid.backendFluidParaformer
                || $0.backend == ModelGrid.backendFluidSenseVoice
        }
        #expect(all.count == 2)
        let defaultSweep = ModelGrid.rows(
            backend: ModelGrid.backendFluidParaformer, priorityCeiling: 1)
        #expect(defaultSweep.isEmpty)  // shelved at priority 2 (decode bug)
        let sv = ModelGrid.rows(backend: ModelGrid.backendFluidSenseVoice, priorityCeiling: 1)
        #expect(sv.count == 1)
        #expect(sv[0].verified)
    }

    @Test func `Pipeline is created once per model and reused`() async throws {
        actor Counter {
            var value = 0
            func bump() { value += 1 }
        }
        let counter = Counter()
        let engine = ChineseFamilyEngine(
            id: .fluidSenseVoice,
            probeDuration: { _ in 1.0 },
            pipelineFactory: { _ in
                await counter.bump()
                return SpyPipeline { _, _ in "x" }
            })
        _ = try await engine.transcribeRaw(audioPath: "a.wav", options: options)
        _ = try await engine.transcribeRaw(audioPath: "b.wav", options: options)
        #expect(await counter.value == 1)
    }
}
