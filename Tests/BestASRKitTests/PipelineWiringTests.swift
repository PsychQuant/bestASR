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
        let tokenizer: (any WhisperTokenizer)?
        init(tokenizer: (any WhisperTokenizer)? = nil) { self.tokenizer = tokenizer }

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
        let spy = SpyPipeline(tokenizer: FakeTokenizer())  // tokenizer PRESENT (#12) —
        // nil-tokenizer made this canary vacuous; with one wired in, nil now proves
        // the gate is the absent prompt, not the absent tokenizer.
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

    /// #12: deterministic fake — UTF-8 bytes as token ids, so assertions can
    /// state the exact expected encoding (leading space included) without a
    /// real vocabulary. Everything else is inert stubbing.
    struct FakeTokenizer: WhisperTokenizer {
        func encode(text: String) -> [Int] { Array(text.utf8).map(Int.init) }
        func decode(tokens: [Int]) -> String {
            String(decoding: tokens.compactMap { UInt8(exactly: $0) }, as: UTF8.self)
        }
        func convertTokenToId(_ token: String) -> Int? { nil }
        func convertIdToToken(_ id: Int) -> String? { nil }
        var specialTokens: SpecialTokens {
            SpecialTokens(
                endToken: 0, englishToken: 0, noSpeechToken: 0, noTimestampsToken: 0,
                specialTokenBegin: 0, startOfPreviousToken: 0, startOfTranscriptToken: 0,
                timeTokenBegin: 0, transcribeToken: 0, translateToken: 0, whitespaceToken: 0)
        }
        var allLanguageTokens: Set<Int> { [] }
        func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) { ([], []) }
    }

    /// #12: the prompt-encode branch (encode → clamp → makeDecodeOptions) had no
    /// seam coverage — #9's spy injected tokenizer: nil, so deleting the branch
    /// kept every test green (DA-proven). This locks the actual wiring: the
    /// pipeline receives EXACTLY the encoding of " " + prompt (leading space
    /// preserved — Whisper conditioning convention).
    @Test func `Prompt encodes through the tokenizer and reaches the pipeline`() async throws {
        let spy = SpyPipeline(tokenizer: FakeTokenizer())
        let engine = WhisperKitEngine(pipelineFactory: { _ in spy })
        _ = try await engine.transcribe(
            audioPath: "unused.wav",
            options: TranscribeOptions(
                model: "wiring-spy-prompt", quantization: "default", language: "en",
                prompt: "Kalman filter, Kokoro")
        )
        let sent = try #require(spy.lastOptions)
        let expected = FakeTokenizer().encode(text: " Kalman filter, Kokoro")
        #expect(sent.promptTokens == expected)          // exact wiring, not just non-nil
        #expect(expected.first == 32)                   // " " survived — leading space in-band
    }

    /// #12: the 224-token clamp must act on the ENCODED prompt at the seam —
    /// keeping the suffix (nearest context wins under Whisper's left-context
    /// window), not the prefix.
    @Test func `Overlong prompt is clamped to the trailing 224 tokens at the seam`() async throws {
        let spy = SpyPipeline(tokenizer: FakeTokenizer())
        let engine = WhisperKitEngine(pipelineFactory: { _ in spy })
        let longPrompt = String(repeating: "a", count: 300)
        _ = try await engine.transcribe(
            audioPath: "unused.wav",
            options: TranscribeOptions(
                model: "wiring-spy-clamp", quantization: "default", language: "en",
                prompt: longPrompt)
        )
        let sent = try #require(spy.lastOptions)
        let full = FakeTokenizer().encode(text: " " + longPrompt)  // 301 tokens
        #expect(sent.promptTokens?.count == 224)
        #expect(sent.promptTokens == Array(full.suffix(224)))
    }
}
