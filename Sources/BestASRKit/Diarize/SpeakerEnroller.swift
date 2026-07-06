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
            // #52 (spec weight-pinning): diarizer weights span two repos.
            try WeightVerifier.verifyBundled(repo: "speaker-diarization")
            try WeightVerifier.verifyBundled(repo: "silero-vad-coreml")
            let diarizer = DiarizerManager()
            diarizer.initialize(models: models)
            let samples = try AudioConverter()
                .resampleAudioFile(URL(fileURLWithPath: audioPath))
            let result = try diarizer.performCompleteDiarization(samples)

            // Dominant speaker = most total speaking time (a brief cough must not
            // out-vote the enrolled voice); its embedding = that speaker's LONGEST
            // single segment (the cleanest, most representative sample rather than
            // an arbitrary first fragment — #26 verify F32/F10).
            var durationById: [String: Double] = [:]
            var bestSegById: [String: (duration: Float, embedding: [Float])] = [:]
            for seg in result.segments {
                let dur = seg.endTimeSeconds - seg.startTimeSeconds
                durationById[seg.speakerId, default: 0] += Double(dur)
                if bestSegById[seg.speakerId] == nil || dur > bestSegById[seg.speakerId]!.duration {
                    bestSegById[seg.speakerId] = (dur, seg.embedding)
                }
            }
            guard let dominant = durationById.max(by: { $0.value < $1.value })?.key else { return nil }
            return bestSegById[dominant]?.embedding
        } catch {
            throw TranscriptionError(
                backend: "diarization",
                message: "speaker enrollment failed for \(audioPath): \(error.localizedDescription)",
                underlying: error)
        }
    }
}
