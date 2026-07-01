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

        var decodeOptions = DecodingOptions()
        decodeOptions.language = options.language
        decodeOptions.detectLanguage = options.language == nil

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
