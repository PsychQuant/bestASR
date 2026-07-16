import Foundation

/// How aggressively to strip decoder hallucinations before a transcript is
/// written. Selected once per transcription and applied at the single output
/// choke point, so every surface (CLI / MCP / GUI) shares one behavior.
public enum HallucinationFilterMode: String, Sendable, CaseIterable {
    /// No filtering — emit the raw transcript (escape hatch / A-B comparison).
    case off
    /// Strip cues matching the known-boilerplate denylist, and collapse empty /
    /// adjacent-duplicate cues. Backend-agnostic; the denylist content is
    /// Whisper-family, so it is a no-op for backends that never emit it.
    case denylist
    /// Everything `denylist` does, plus confidence-gated drops on Whisper's
    /// per-segment signals (#100): the joint silence rule (noSpeechProb AND
    /// avgLogprob past threshold, openai-whisper semantics) and the repetition
    /// rule (compressionRatio past threshold). Backends that don't populate the
    /// signals degrade to `denylist` behavior — nil never trips a threshold.
    case full
}

/// Post-decode cleanup pass. A pure function over a `Transcript` that never
/// touches timing — it only drops whole cues and re-derives the flat text.
///
/// It sits at the single output choke point (`CommandCore.transcribe`), *after*
/// diarization, which makes it backend-agnostic and preserves speaker labels on
/// the cues that survive.
public enum HallucinationFilter {
    /// Whisper's canonical thresholds (openai/whisper defaults). The silence
    /// rule is deliberately a conjunction — a high no-speech probability alone
    /// (or a low logprob alone) also occurs on quiet-but-real speech.
    static let noSpeechThreshold = 0.6
    static let logProbThreshold = -1.0
    static let compressionRatioThreshold = 2.4

    /// True when the segment's confidence signals mark it as a hallucination
    /// (`full` mode only). nil signals never trip a rule.
    static func isConfidenceFlagged(_ segment: TranscriptSegment) -> Bool {
        if let noSpeech = segment.noSpeechProb, let logProb = segment.confidence,
            noSpeech > noSpeechThreshold, logProb < logProbThreshold {
            return true
        }
        if let compression = segment.compressionRatio, compression > compressionRatioThreshold {
            return true
        }
        return false
    }

    /// Return `transcript` with hallucination cues removed per `mode`.
    /// A no-op (`mode == .off`, or nothing matched) returns the input untouched
    /// so ids and flat text stay byte-identical.
    public static func filter(
        _ transcript: Transcript,
        mode: HallucinationFilterMode,
        denylist: HallucinationDenylist = .default
    ) -> Transcript {
        guard mode != .off else { return transcript }

        var kept: [TranscriptSegment] = []
        for segment in transcript.segments {
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Empty cue — nothing was said (common over silence).
            if trimmed.isEmpty { continue }
            // Known-boilerplate hallucination.
            if denylist.matches(segment.text) { continue }
            // Confidence-gated drop (full mode only, #100).
            if mode == .full, isConfidenceFlagged(segment) { continue }
            // Adjacent exact-duplicate cue (rolling caption / token echo).
            if let previous = kept.last,
                previous.text.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
                continue
            }
            kept.append(segment)
        }

        // Nothing removed → return the original untouched so ids and flat text
        // stay byte-identical when the filter is a no-op.
        guard kept.count != transcript.segments.count else { return transcript }

        // Re-index survivors 1…N (json / id consumers expect contiguous ids) and
        // re-derive the flat text the exact way an engine does — see
        // Engines/Engine.swift — so txt / json reflect the cleaned cues too.
        let reindexed = kept.enumerated().map { index, segment in
            TranscriptSegment(
                id: index + 1, start: segment.start, end: segment.end,
                text: segment.text, confidence: segment.confidence,
                noSpeechProb: segment.noSpeechProb, compressionRatio: segment.compressionRatio,
                speaker: segment.speaker)
        }
        let rebuiltText = reindexed.map(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Transcript(
            text: rebuiltText, language: transcript.language,
            duration: transcript.duration, backend: transcript.backend,
            model: transcript.model, segments: reindexed)
    }
}
