import Foundation
import Testing
import WhisperKit
@testable import BestASRKit

/// #9: lock the transcribeRaw → makeDecodeOptions wiring at the production
/// path. A spy pipeline captures the DecodingOptions the engine actually
/// sends — if a future edit rebuilds options inline (bypassing the factory),
/// these assertions go red even though DecodeOptionsTests stay green.
struct PipelineWiringTests {
    /// Captures what reaches the pipeline; returns no results (the engine's
    /// normalization handles empty output).
    final class SpyPipeline: TranscribingPipeline, @unchecked Sendable {
        private let lock = NSLock()
        private var captured: [DecodingOptions] = []
        var tokenizer: (any WhisperTokenizer)? { nil }

        func transcribe(
            audioPath: String, decodeOptions: DecodingOptions?
        ) async throws -> [TranscriptionResult] {
            lock.lock()
            defer { lock.unlock() }
            if let decodeOptions { captured.append(decodeOptions) }
            return []
        }

        var lastOptions: DecodingOptions? {
            lock.lock()
            defer { lock.unlock() }
            return captured.last
        }
    }

    @Test func `Production path sends skipSpecialTokens to the pipeline`() async throws {
        let spy = SpyPipeline()
        let engine = WhisperKitEngine(pipelineFactory: { _ in spy })
        _ = try await engine.transcribe(
            audioPath: "unused.wav",
            options: TranscribeOptions(model: "wiring-spy", quantization: "default", language: "en")
        )
        let sent = try #require(spy.lastOptions)
        #expect(sent.skipSpecialTokens == true)  // the #6 wiring lock
        #expect(sent.language == "en")
        #expect(sent.detectLanguage == false)
    }

    @Test func `Auto language flows to the pipeline as detection`() async throws {
        let spy = SpyPipeline()
        let engine = WhisperKitEngine(pipelineFactory: { _ in spy })
        _ = try await engine.transcribe(
            audioPath: "unused.wav",
            options: TranscribeOptions(model: "wiring-spy-auto", quantization: "default")
        )
        let sent = try #require(spy.lastOptions)
        #expect(sent.detectLanguage == true)
        #expect(sent.promptTokens == nil)  // no prompt, nothing leaks in
    }

    /// DA mutation finding: defeating the cache left all tests green — this
    /// locks the #7 reuse guarantee at the wiring level (factory runs once
    /// per key per engine; distinct keys and distinct engines stay isolated).
    @Test func `Same engine reuses the cached pipeline across calls`() async throws {
        let counter = CreateOnceStoreTests.Counter()
        let engine = WhisperKitEngine(pipelineFactory: { _ in
            _ = await counter.bump()
            return SpyPipeline()
        })
        let options = TranscribeOptions(model: "reuse-spy", quantization: "default", language: "en")
        _ = try await engine.transcribe(audioPath: "a.wav", options: options)
        _ = try await engine.transcribe(audioPath: "b.wav", options: options)
        #expect(await counter.count == 1)  // warm-up→timed reuse (#7) at the wiring level
    }

    @Test func `Distinct engines and distinct keys do not share pipelines`() async throws {
        let counter = CreateOnceStoreTests.Counter()
        let factory: @Sendable (String) async throws -> any TranscribingPipeline = { _ in
            _ = await counter.bump()
            return SpyPipeline()
        }
        let engineA = WhisperKitEngine(pipelineFactory: factory)
        let engineB = WhisperKitEngine(pipelineFactory: factory)
        let options = TranscribeOptions(model: "iso-spy", quantization: "default", language: "en")
        _ = try await engineA.transcribe(audioPath: "a.wav", options: options)
        _ = try await engineB.transcribe(audioPath: "a.wav", options: options)  // separate store
        _ = try await engineA.transcribe(
            audioPath: "a.wav",
            options: TranscribeOptions(model: "iso-spy-2", quantization: "default", language: "en"))
        #expect(await counter.count == 3)  // A:key1 + B:key1 + A:key2
    }
}
