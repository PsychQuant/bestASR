import Foundation
import WhisperKit

/// The slice of WhisperKit the engine consumes — a seam (#9) so tests can
/// spy on the DecodingOptions actually reaching the pipeline without loading
/// a real CoreML model.
protocol TranscribingPipeline {
    var tokenizer: (any WhisperTokenizer)? { get }
    func transcribe(
        audioPath: String, decodeOptions: DecodingOptions?
    ) async throws -> [TranscriptionResult]
}

extension WhisperKit: TranscribingPipeline {
    // Explicit witness: WhisperKit's own transcribe carries a defaulted
    // `callback` parameter, and defaulted parameters cannot satisfy a
    // protocol requirement. The return-type annotation picks the
    // [TranscriptionResult] overload (a TranscriptionResult? sibling exists).
    func transcribe(
        audioPath: String, decodeOptions: DecodingOptions?
    ) async throws -> [TranscriptionResult] {
        try await transcribe(audioPath: audioPath, decodeOptions: decodeOptions, callback: nil)
    }
}

/// WhisperKit backend — CoreML/ANE path (design D3, primary).
///
/// WhisperKit is compiled into the binary, so on any supported host (Apple
/// Silicon, macOS 14+ — both guaranteed by the platform gate) it is always
/// available; models download on demand at first use.
public struct WhisperKitEngine: Engine {
    public let id: BackendID = .whisperKit

    public init() {
        self.init(pipelineFactory: { model in
            try await WhisperKit(WhisperKitConfig(model: model, download: true))
        })
    }

    /// Internal seam (#9): tests inject a spy; the public surface stays free
    /// of WhisperKit types (Sendable posture of the seam remains a module-
    /// internal concern under the repo's Swift 5 language-mode convention).
    init(
        pipelineFactory: @escaping @Sendable (String) async throws -> any TranscribingPipeline
    ) {
        self.pipelineFactory = pipelineFactory
    }

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
        // Empty non-nil is NOT nil-equivalent in WhisperKit 0.18 (a stray
        // <|startofprev|> enters the decoder context and prefill caching is
        // silently disabled) — guard here so the factory is safe for any caller.
        if let promptTokens, !promptTokens.isEmpty {
            decodeOptions.promptTokens = promptTokens
            decodeOptions.usePrefillPrompt = true
        }
        return decodeOptions
    }

    /// Injectable pipeline construction (#9): production builds WhisperKit;
    /// tests inject a spy. The factory receives the resolved model name.
    let pipelineFactory: @Sendable (String) async throws -> any TranscribingPipeline

    /// Per-instance pipeline cache (#7): rebuilding WhisperKit per call
    /// re-paid the CoreML model load inside benchmark's TIMED pass, violating
    /// the benchmark spec's "model download and first-load time are excluded
    /// from RTF" and under-reporting WhisperKit X-REAL by an order of
    /// magnitude. The warm-up pass now populates this store; later calls for
    /// the same model reuse the loaded pipeline. Trade-off: cached models
    /// stay resident for the engine's lifetime (in the CLI, one engine per
    /// process, so engine lifetime = process lifetime) — acceptable for a CLI whose
    /// benchmark loads them anyway.
    /// Instance-scoped (not static) so injected test pipelines never leak
    /// across engines; the CLI builds one engine per process, so warm-up→timed
    /// reuse within a run is unchanged.
    let pipelines = CreateOnceStore<any TranscribingPipeline>()

    public func transcribeRaw(
        audioPath: String, options: TranscribeOptions
    ) async throws -> RawTranscription {
        let modelName = Self.whisperKitModelName(for: options.model)
        // Key carries quantization (issue #7 Expected) even though WhisperKit
        // currently ships a single "default" variant per model.
        let cacheKey = "\(modelName)|\(options.quantization)"
        let pipe: any TranscribingPipeline
        do {
            // Keep only the current model resident (see retainOnly rationale).
            await pipelines.retainOnly(cacheKey)
            let factory = pipelineFactory
            pipe = try await pipelines.value(for: cacheKey) {
                try await factory(modelName)
            }
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
