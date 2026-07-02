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
}
