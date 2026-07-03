import Foundation

/// One diarized speaker turn: who (raw engine id) spoke over [start, end).
public struct SpeakerTurn: Sendable, Equatable {
    public let speaker: String
    public let start: Double
    public let end: Double

    public init(speaker: String, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

/// Cue-level speaker assignment (spec diarization; #25 design D1).
///
/// Pure by design: the FluidAudio engine produces turns, transcription produces
/// segments, and this is the only place the two meet — fully unit-testable
/// without models or audio.
public enum SpeakerAssigner {
    /// For each segment, the speaker whose turn overlaps it the most.
    /// Zero overlap → nil (unknown, never fabricated). Ties (within a 1ns
    /// epsilon — engine times are Doubles, exact `==` would let a rounding
    /// ULP defeat the rule) → the earlier-starting turn.
    ///
    /// A winning turn whose raw speaker id is in `knownNames` (an enrolled
    /// voice, #26) is labeled with that name verbatim; every other speaker
    /// gets a `SPEAKER_N` ordinal in order of first appearance. Enrolled names
    /// do NOT consume ordinal numbers — strangers are numbered as if the known
    /// speakers were not present, so their numbering is stable regardless of
    /// which voices happen to be enrolled.
    public static func assign(
        segments: [TranscriptSegment], turns: [SpeakerTurn],
        knownNames: Set<String> = []
    ) -> [String?] {
        var ordinalByRawId: [String: Int] = [:]
        var next = 1
        return segments.map { seg in
            var best: (turn: SpeakerTurn, overlap: Double)?
            let epsilon = 1e-9
            for turn in turns {
                let overlap = min(seg.end, turn.end) - max(seg.start, turn.start)
                guard overlap > 0 else { continue }
                if let current = best {
                    if overlap > current.overlap + epsilon
                        || (abs(overlap - current.overlap) <= epsilon
                            && turn.start < current.turn.start)
                    {
                        best = (turn, overlap)
                    }
                } else {
                    best = (turn, overlap)
                }
            }
            guard let winner = best?.turn else { return nil }
            if knownNames.contains(winner.speaker) { return winner.speaker }
            if ordinalByRawId[winner.speaker] == nil {
                ordinalByRawId[winner.speaker] = next
                next += 1
            }
            return "SPEAKER_\(ordinalByRawId[winner.speaker]!)"
        }
    }
}
