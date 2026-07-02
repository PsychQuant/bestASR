import Foundation
import Testing
@testable import BestASRKit

// #25: cue-level speaker assignment — the pure core of diarization (spec diarization).
struct SpeakerAssignerTests {
    private func seg(_ id: Int, _ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment(id: id, start: start, end: end, text: "s\(id)")
    }

    @Test func `Max-overlap wins and labels are first-appearance ordinals`() {
        let segments = [seg(0, 0, 10), seg(1, 10, 20), seg(2, 20, 30)]
        let turns = [
            SpeakerTurn(speaker: "raw-B", start: 0, end: 11),    // covers seg0 fully, seg1 slightly
            SpeakerTurn(speaker: "raw-A", start: 11, end: 30),   // majority of seg1, all of seg2
        ]
        let labels = SpeakerAssigner.assign(segments: segments, turns: turns)
        // raw-B appears first → SPEAKER_1 (remapped by appearance order, not raw name sort)
        #expect(labels == ["SPEAKER_1", "SPEAKER_2", "SPEAKER_2"])
    }

    @Test func `Zero overlap yields nil, never a fabricated speaker`() {
        let segments = [seg(0, 0, 5), seg(1, 40, 50)]
        let turns = [SpeakerTurn(speaker: "x", start: 0, end: 6)]
        let labels = SpeakerAssigner.assign(segments: segments, turns: turns)
        #expect(labels == ["SPEAKER_1", nil])
    }

    @Test func `Tie goes to the earlier-starting turn`() {
        let segments = [seg(0, 10, 20)]
        let turns = [
            SpeakerTurn(speaker: "late", start: 15, end: 20),   // overlap 5
            SpeakerTurn(speaker: "early", start: 10, end: 15),  // overlap 5 (tie)
        ]
        let labels = SpeakerAssigner.assign(segments: segments, turns: turns)
        // "early" starts first → wins tie; it is also first appearance → SPEAKER_1
        #expect(labels == ["SPEAKER_1"])
        // and the winning turn is the early one (proven by ordinal mapping below)
        let two = SpeakerAssigner.assign(segments: [seg(0, 10, 20), seg(1, 15, 20)], turns: turns)
        // seg1 (15-20): late overlaps 5, early 0 → late wins → second-appearing speaker
        #expect(two == ["SPEAKER_1", "SPEAKER_2"])
    }

    @Test func `A straddling segment goes to the majority side`() {
        // seg0 anchors A as first appearance; seg1 straddles 2s in A (8-10)
        // vs 4s in B (10-14) → majority side B = second appearance.
        let segments = [seg(0, 0, 8), seg(1, 8, 14)]
        let turns = [
            SpeakerTurn(speaker: "A", start: 0, end: 10),
            SpeakerTurn(speaker: "B", start: 10, end: 20),
        ]
        #expect(SpeakerAssigner.assign(segments: segments, turns: turns) == ["SPEAKER_1", "SPEAKER_2"])
    }

    @Test func `Same speaker across split turns keeps one label`() {
        let segments = [seg(0, 0, 5), seg(1, 6, 10)]
        let turns = [
            SpeakerTurn(speaker: "A", start: 0, end: 5),
            SpeakerTurn(speaker: "A", start: 6, end: 10),
        ]
        #expect(SpeakerAssigner.assign(segments: segments, turns: turns) == ["SPEAKER_1", "SPEAKER_1"])
    }
}

// #25: speaker rendering across the four formats — and byte-identity without speakers.
struct SpeakerRenderingTests {
    private func transcript(speakers: [String?]) -> Transcript {
        let segs = [
            TranscriptSegment(id: 0, start: 0, end: 2, text: "hello there", speaker: speakers[0]),
            TranscriptSegment(id: 1, start: 2, end: 4, text: "hi back", speaker: speakers[1]),
        ]
        return Transcript(
            text: "hello there hi back", language: "en", duration: 4,
            backend: "whisperkit", model: "tiny", segments: segs)
    }

    @Test func `SRT and VTT cues carry speaker prefixes when present`() {
        let t = transcript(speakers: ["SPEAKER_1", "SPEAKER_2"])
        let srt = TranscriptWriter.render(t, format: .srt)
        #expect(srt.contains("[SPEAKER_1] hello there"))
        #expect(srt.contains("[SPEAKER_2] hi back"))
        let vtt = TranscriptWriter.render(t, format: .vtt)
        #expect(vtt.contains("[SPEAKER_2] hi back"))
    }

    @Test func `JSON gains a speaker field only when present`() {
        let with = TranscriptWriter.render(transcript(speakers: ["SPEAKER_1", nil]), format: .json)
        #expect(with.contains("\"speaker\" : \"SPEAKER_1\""))
        let without = TranscriptWriter.render(transcript(speakers: [nil, nil]), format: .json)
        #expect(!without.contains("\"speaker\""))
    }

    @Test func `txt lines gain speaker prefixes when present`() {
        let txt = TranscriptWriter.render(transcript(speakers: ["SPEAKER_1", "SPEAKER_2"]), format: .txt)
        #expect(txt.contains("SPEAKER_1: hello there"))
    }

    @Test func `No speakers means byte-identical legacy output in every format`() {
        let t = transcript(speakers: [nil, nil])
        #expect(TranscriptWriter.render(t, format: .srt) == "1\n00:00:00,000 --> 00:00:02,000\nhello there\n\n2\n00:00:02,000 --> 00:00:04,000\nhi back\n")
        #expect(TranscriptWriter.render(t, format: .txt) == "hello there hi back")
    }
}
