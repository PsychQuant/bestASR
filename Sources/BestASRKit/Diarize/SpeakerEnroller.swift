import FluidAudio
import Foundation

/// Turns an enrollment voice sample into a speaker embedding for known-speaker
/// recognition (spec diarization; #26 design D1).
///
/// Reuses the same FluidAudio pipeline as diarization: diarize the sample, then
/// take the embedding of the speaker with the greatest total speaking time
/// (a brief cough or background noise must not out-vote the enrolled voice).
public struct SpeakerEnroller: Sendable {
    public init() {}

    /// The dominant speaker embedding for one enrollment sample, or nil when the
    /// sample yields no usable speaker (too short / silent).
    public func embedding(for audioPath: String) async throws -> [Float]? {
        do {
            let models = try await DiarizerModels.downloadIfNeeded()
            let diarizer = DiarizerManager()
            diarizer.initialize(models: models)
            let samples = try AudioConverter()
                .resampleAudioFile(URL(fileURLWithPath: audioPath))
            let result = try diarizer.performCompleteDiarization(samples)

            // Dominant speaker's embedding: the id with the most speaking time
            // (a brief cough must not out-vote the enrolled voice), taken from
            // its segment embedding.
            var durationById: [String: Double] = [:]
            var embeddingById: [String: [Float]] = [:]
            for seg in result.segments {
                durationById[seg.speakerId, default: 0] +=
                    Double(seg.endTimeSeconds - seg.startTimeSeconds)
                if embeddingById[seg.speakerId] == nil { embeddingById[seg.speakerId] = seg.embedding }
            }
            guard let dominant = durationById.max(by: { $0.value < $1.value })?.key else { return nil }
            return embeddingById[dominant]
        } catch {
            throw TranscriptionError(
                backend: "diarization",
                message: "speaker enrollment failed for \(audioPath): \(error.localizedDescription)",
                underlying: error)
        }
    }
}
