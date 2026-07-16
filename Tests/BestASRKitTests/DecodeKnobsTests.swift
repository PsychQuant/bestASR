import Foundation
import Testing
import WhisperKit

@testable import BestASRKit

/// spec asr-engine (#101): WhisperKit decode-param knobs. nil = ride
/// WhisperKit's own defaults (the pre-#101 behavior, byte-for-byte).
struct DecodeKnobsTests {
    @Test func `set thresholds reach DecodingOptions`() {
        let options = WhisperKitEngine.makeDecodeOptions(
            language: "en", promptTokens: nil,
            noSpeechThreshold: 0.5, compressionRatioThreshold: 2.0, logProbThreshold: -0.8)
        #expect(options.noSpeechThreshold == 0.5)
        #expect(options.compressionRatioThreshold == 2.0)
        #expect(options.logProbThreshold == -0.8)
    }

    @Test func `unset thresholds keep WhisperKit defaults`() {
        let ours = WhisperKitEngine.makeDecodeOptions(language: "en", promptTokens: nil)
        let stock = DecodingOptions()
        #expect(ours.noSpeechThreshold == stock.noSpeechThreshold)
        #expect(ours.compressionRatioThreshold == stock.compressionRatioThreshold)
        #expect(ours.logProbThreshold == stock.logProbThreshold)
    }

    @Test func `TranscribeOptions carries the knobs with nil defaults`() {
        let plain = TranscribeOptions(model: "base", quantization: "default")
        #expect(plain.noSpeechThreshold == nil)
        #expect(plain.compressionRatioThreshold == nil)
        #expect(plain.logProbThreshold == nil)

        let tuned = TranscribeOptions(
            model: "base", quantization: "default",
            noSpeechThreshold: 0.7, compressionRatioThreshold: 2.2, logProbThreshold: -1.2)
        #expect(tuned.noSpeechThreshold == 0.7)
        #expect(tuned != plain)
    }
}
