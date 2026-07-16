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
}

/// Post-decode cleanup pass. A pure function over a `Transcript` that never
/// touches timing — it only drops whole cues and re-derives the flat text.
///
/// It sits at the single output choke point (`CommandCore.transcribe`), *after*
/// diarization, which makes it backend-agnostic and preserves speaker labels on
/// the cues that survive.
public enum HallucinationFilter {
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
                text: segment.text, confidence: segment.confidence, speaker: segment.speaker)
        }
        let rebuiltText = reindexed.map(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Transcript(
            text: rebuiltText, language: transcript.language,
            duration: transcript.duration, backend: transcript.backend,
            model: transcript.model, segments: reindexed)
    }
}
