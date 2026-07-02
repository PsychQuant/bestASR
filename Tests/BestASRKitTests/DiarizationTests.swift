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


// #25 verify fixes: the diarize path through CommandCore via the injected seam —
// labels applied end-to-end, empty yield fails loudly (D4 soft-failure), and
// diarize:false never touches the acoustic layer.
struct DiarizePathTests {
    private func core(
        in dir: URL,
        diarizer: @escaping @Sendable (String) async throws -> [SpeakerTurn]
    ) -> CommandCore {
        CommandCore(
            engines: [MockEngine.fixed(.whisperKit)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            probe: .live(),  // transcribe 路徑不量測——live probe 無害
            diarizer: diarizer)
    }

    private func selection() -> SelectionRequest {
        SelectionRequest(
            profileName: "balanced", backendOverride: nil, modelOverride: nil,
            requestedLanguage: "en", contextDir: nil)
    }

    @Test func `Diarize labels flow through to the written SRT`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let core = core(in: dir) { _ in [SpeakerTurn(speaker: "x", start: 0, end: 2.5)] }

        let outcome = try await core.transcribe(
            audioPath: audio, selection: selection(), formatName: "srt",
            outputPath: dir.appendingPathComponent("out.srt").path, diarize: true)
        let srt = try String(contentsOfFile: outcome.outputPath, encoding: .utf8)
        #expect(srt.contains("[SPEAKER_1] hello world"))
    }

    @Test func `An all-unlabeled diarize run fails loudly instead of emitting clean output`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let core = core(in: dir) { _ in [] }  // engine "succeeds" with zero turns

        await #expect(throws: BestASRError.self) {
            _ = try await core.transcribe(
                audioPath: audio, selection: selection(), formatName: "srt",
                outputPath: dir.appendingPathComponent("out.srt").path, diarize: true)
        }
    }

    @Test func `Without the flag the acoustic layer is never invoked`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let core = core(in: dir) { _ in
            Issue.record("diarizer must not run without --diarize")
            return []
        }

        let outcome = try await core.transcribe(
            audioPath: audio, selection: selection(), formatName: "srt",
            outputPath: dir.appendingPathComponent("out.srt").path, diarize: false)
        let srt = try String(contentsOfFile: outcome.outputPath, encoding: .utf8)
        #expect(!srt.contains("SPEAKER"))
    }
}

// #25 verify fix F3/F8: byte-pin the remaining two no-speaker formats so the
// "every format byte-identical" claim is fully unit-pinned.
struct NoSpeakerBytePinTests {
    private var transcript: Transcript {
        Transcript(
            text: "hello world", language: "en", duration: 2.5,
            backend: "whisperkit", model: "tiny",
            segments: [TranscriptSegment(id: 0, start: 0, end: 2.5, text: "hello world")])
    }

    @Test func `VTT without speakers is byte-identical to legacy`() {
        #expect(TranscriptWriter.render(transcript, format: .vtt)
            == "WEBVTT\n\n00:00:00.000 --> 00:00:02.500\nhello world\n")
    }

    @Test func `JSON without speakers is byte-identical to legacy`() {
        let json = TranscriptWriter.render(transcript, format: .json)
        #expect(json == """
        {
          "backend" : "whisperkit",
          "duration" : 2.5,
          "language" : "en",
          "model" : "tiny",
          "segments" : [
            {
              "end" : 2.5,
              "id" : 0,
              "start" : 0,
              "text" : "hello world"
            }
          ],
          "text" : "hello world"
        }
        """)
    }
}
