import FluidAudio
import Foundation

/// Acoustic speaker diarization over a whole audio file (spec diarization; #25).
///
/// Thin wrapper around FluidAudio's batch pipeline (pinned v0.15.4, design D3):
/// CoreML models are fetched and cached by the vendored SDK on first use
/// (trusted-vendor boundary — the SDK manages its own model revisions and
/// supports an offline mode). Failures throw: with `--diarize` explicitly
/// requested, degrading silently to unlabeled output is forbidden (design D4).
public struct DiarizationEngine: Sendable {
    public init() {}

    /// Diarize the file and return raw speaker turns (engine ids, seconds).
    /// Label remapping to `SPEAKER_N` ordinals happens in `SpeakerAssigner`
    /// at assignment time — the ordinals depend on which turns actually win
    /// segments, not on raw engine order.
    public func diarize(audioPath: String) async throws -> [SpeakerTurn] {
        do {
            let models = try await DiarizerModels.downloadIfNeeded()
            let diarizer = DiarizerManager()
            diarizer.initialize(models: models)
            let samples = try AudioConverter()
                .resampleAudioFile(URL(fileURLWithPath: audioPath))
            let result = try diarizer.performCompleteDiarization(samples)
            return result.segments.map {
                SpeakerTurn(
                    speaker: $0.speakerId,
                    start: Double($0.startTimeSeconds),
                    end: Double($0.endTimeSeconds))
            }
        } catch {
            throw TranscriptionError(
                backend: "diarization",
                message: "speaker diarization failed: \(error.localizedDescription)",
                underlying: error)
        }
    }
}
