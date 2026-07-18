import Foundation
import WhisperKit

/// Detects the spoken language of an audio file so `--language auto` can rank
/// with a language-aware candidate pool (#105). Seam protocol: tests inject
/// fakes; production uses the smallest multilingual WhisperKit model.
public protocol AudioLanguageDetecting: Sendable {
    /// The detected language code ("zh", "en", …) for the audio at `audioPath`.
    func detectLanguage(audioPath: String) async throws -> String
}

/// WhisperKit-backed detector. Loads the smallest multilingual model (tiny —
/// downloads on demand at first use like every WhisperKit engine model) and
/// reads only the first 30 s of audio (WhisperKit's own detection window).
public struct WhisperKitLanguageDetector: AudioLanguageDetecting {
    public init() {}

    public func detectLanguage(audioPath: String) async throws -> String {
        let pipeline = try await WhisperKit(WhisperKitConfig(model: "tiny", download: true))
        return try await pipeline.detectLanguage(audioPath: audioPath).language
    }
}
