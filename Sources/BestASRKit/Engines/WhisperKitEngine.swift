import Foundation
import WhisperKit

/// WhisperKit backend — CoreML/ANE path (design D3, primary).
///
/// WhisperKit is compiled into the binary, so on any supported host (Apple
/// Silicon, macOS 14+ — both guaranteed by the platform gate) it is always
/// available; models download on demand at first use.
public struct WhisperKitEngine: Engine {
    public let id: BackendID = .whisperKit

    public init() {}

    public func isAvailable() async -> Bool {
        true
    }

    /// Our registry names → WhisperKit model-search names (verified against the
    /// resolved WhisperKit 0.18 checkout; the turbo variant uses an underscore
    /// in the argmaxinc/whisperkit-coreml repo naming).
    static func whisperKitModelName(for model: String) -> String {
        switch model {
        case "large-v3-turbo": "large-v3_turbo"
        default: model
        }
    }

    /// Whisper's practical prompt window is ~224 tokens; the renderer budgets
    /// ~200 with a heuristic, this clamp is the tokenizer-measured net.
    static func clampedPromptTokens(_ tokens: [Int], limit: Int = 224) -> [Int] {
        tokens.count <= limit ? tokens : Array(tokens.suffix(limit))
    }

    /// Decode options for one run. skipSpecialTokens MUST stay true: without it
    /// WhisperKit returns `<|startoftranscript|>`/timestamp tokens inside
    /// segment text, polluting transcripts and inflating WER (#6 — caught by
    /// real-model verification against jfk.wav / OSR Harvard).
    static func makeDecodeOptions(language: String?, promptTokens: [Int]?) -> DecodingOptions {
        var decodeOptions = DecodingOptions()
        decodeOptions.language = language
        decodeOptions.detectLanguage = language == nil
        decodeOptions.skipSpecialTokens = true
        if let promptTokens {
            decodeOptions.promptTokens = promptTokens
            decodeOptions.usePrefillPrompt = true
        }
        return decodeOptions
    }

    public func transcribeRaw(
        audioPath: String, options: TranscribeOptions
    ) async throws -> RawTranscription {
        let config = WhisperKitConfig(
            model: Self.whisperKitModelName(for: options.model),
            download: true
        )
        let pipe: WhisperKit
        do {
            pipe = try await WhisperKit(config)
        } catch {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "failed to load model '\(options.model)': \(error.localizedDescription)",
                underlying: error
            )
        }

        var promptTokens: [Int]?
        if let prompt = options.prompt, let tokenizer = pipe.tokenizer {
            // Context prompt (spec asr-engine): conditioning tokens prepended to
            // the prefill; clamped as a safety net under Whisper's ~224 limit.
            let tokens = Self.clampedPromptTokens(tokenizer.encode(text: " " + prompt))
            if !tokens.isEmpty { promptTokens = tokens }
        }
        let decodeOptions = Self.makeDecodeOptions(
            language: options.language, promptTokens: promptTokens)

        let results = try await pipe.transcribe(audioPath: audioPath, decodeOptions: decodeOptions)
        let segments = results.flatMap(\.segments).map { seg in
            RawTranscription.RawSegment(
                start: Double(seg.start),
                end: Double(seg.end),
                text: seg.text,
                confidence: Double(seg.avgLogprob)
            )
        }
        return RawTranscription(
            segments: segments,
            language: results.first?.language,
            duration: nil
        )
    }
}
