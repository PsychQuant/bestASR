import FluidAudio
import Foundation

/// Acoustic speaker diarization over a whole audio file (spec diarization; #25).
///
/// Thin wrapper around FluidAudio's batch pipeline (pinned v0.15.4, design D3):
/// CoreML models are fetched and cached by the vendored SDK on first use
/// (trusted-vendor boundary — the SDK manages its own model revisions and
/// supports an offline mode). Failures throw: with `--diarize` explicitly
/// requested, degrading silently to unlabeled output is forbidden (design D4).
/// Diarization result: speaker turns plus per-speaker embeddings for
/// post-hoc identification (#26).
public struct DiarizationOutput: Sendable, Equatable {
    public let turns: [SpeakerTurn]
    public let embeddings: [String: [Float]]
    public init(turns: [SpeakerTurn], embeddings: [String: [Float]]) {
        self.turns = turns
        self.embeddings = embeddings
    }
}

public struct DiarizationEngine: Sendable {
    public init() {}

    /// Diarize the file and return raw speaker turns (engine ids, seconds).
    /// Label remapping to `SPEAKER_N` ordinals happens in `SpeakerAssigner`
    /// at assignment time — the ordinals depend on which turns actually win
    /// segments, not on raw engine order.
    public func diarize(audioPath: String) async throws -> DiarizationOutput {
        do {
            let models = try await DiarizerModels.downloadIfNeeded()
            // #52 (spec weight-pinning): DiarizerModels downloads only the
            // speaker-diarization repo (segmentation + embedding) — VAD is a
            // separate FluidAudio subsystem bestASR does not invoke. No
            // download/load split exists on this API, so verification runs
            // post-load here: it protects every later process, not the one
            // that raced a tamper mid-download (documented limitation).
            try WeightVerifier.verifyBundled(repo: "speaker-diarization")
            let diarizer = DiarizerManager()
            diarizer.initialize(models: models)
            let samples = try AudioConverter()
                .resampleAudioFile(URL(fileURLWithPath: audioPath))
            let result = try diarizer.performCompleteDiarization(samples)
            let turns = result.segments.map {
                SpeakerTurn(
                    speaker: $0.speakerId,
                    start: Double($0.startTimeSeconds),
                    end: Double($0.endTimeSeconds))
            }
            // Per-speaker embeddings for post-hoc identification (#26): each id's
            // LONGEST segment embedding (most representative — the first fragment
            // is noisy; #26 verify F32). Works regardless of whether the SDK
            // exposes a speakerDatabase.
            var bestSegById: [String: (duration: Float, embedding: [Float])] = [:]
            for seg in result.segments {
                let dur = seg.endTimeSeconds - seg.startTimeSeconds
                if bestSegById[seg.speakerId] == nil || dur > bestSegById[seg.speakerId]!.duration {
                    bestSegById[seg.speakerId] = (dur, seg.embedding)
                }
            }
            let embeddingById = bestSegById.mapValues(\.embedding)
            return DiarizationOutput(turns: turns, embeddings: embeddingById)
        } catch {
            throw TranscriptionError(
                backend: "diarization",
                message: "speaker diarization failed: \(error.localizedDescription)",
                underlying: error)
        }
    }
}
