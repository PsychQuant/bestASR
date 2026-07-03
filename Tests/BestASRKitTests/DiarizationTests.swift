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
        diarizer: @escaping @Sendable (String) async throws -> DiarizationOutput
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
        let core = core(in: dir) { _ in DiarizationOutput(turns: [SpeakerTurn(speaker: "x", start: 0, end: 2.5)], embeddings: [:]) }

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
        let core = core(in: dir) { _ in DiarizationOutput(turns: [], embeddings: [:]) }  // zero turns

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
            return DiarizationOutput(turns: [], embeddings: [:])
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


// #26: known-speaker labeling — enrolled names pass through verbatim, strangers
// keep stable ordinals, and names never consume an ordinal number.
struct KnownSpeakerAssignerTests {
    private func seg(_ id: Int, _ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment(id: id, start: start, end: end, text: "s\(id)")
    }

    @Test func `An enrolled name passes through verbatim`() {
        let segments = [seg(0, 0, 5)]
        let turns = [SpeakerTurn(speaker: "Alice", start: 0, end: 5)]
        #expect(SpeakerAssigner.assign(
            segments: segments, turns: turns, knownNames: ["Alice"]) == ["Alice"])
    }

    @Test func `Enrolled names do not consume ordinal numbers`() {
        // Alice is known; two strangers must still be SPEAKER_1 and SPEAKER_2,
        // not SPEAKER_2/SPEAKER_3.
        let segments = [seg(0, 0, 5), seg(1, 5, 10), seg(2, 10, 15)]
        let turns = [
            SpeakerTurn(speaker: "raw-x", start: 0, end: 5),
            SpeakerTurn(speaker: "Alice", start: 5, end: 10),
            SpeakerTurn(speaker: "raw-y", start: 10, end: 15),
        ]
        #expect(SpeakerAssigner.assign(
            segments: segments, turns: turns, knownNames: ["Alice"])
            == ["SPEAKER_1", "Alice", "SPEAKER_2"])
    }

    @Test func `A hostile enrollment filename cannot break the cue prefix`() {
        let segments = [seg(0, 0, 5)]
        let turns = [SpeakerTurn(speaker: "ev]il\nname", start: 0, end: 5)]
        // The label reaches [label] SRT prefixes verbatim — strip ] / newline / control.
        #expect(SpeakerAssigner.assign(
            segments: segments, turns: turns, knownNames: ["ev]il\nname"]) == ["evilname"])
    }

    @Test func `No known names is identical to plain diarization`() {
        let segments = [seg(0, 0, 5), seg(1, 5, 10)]
        let turns = [
            SpeakerTurn(speaker: "raw-a", start: 0, end: 5),
            SpeakerTurn(speaker: "raw-b", start: 5, end: 10),
        ]
        #expect(SpeakerAssigner.assign(segments: segments, turns: turns, knownNames: [])
            == SpeakerAssigner.assign(segments: segments, turns: turns))
    }
}


// #26: identification wiring through CommandCore — enrolled voice labels turns
// by name, explain discloses counts, and no-voices behaves like #25.
struct IdentificationPathTests {
    private func core(
        in dir: URL,
        diarizer: @escaping @Sendable (String) async throws -> DiarizationOutput,
        enroller: @escaping @Sendable (String) async throws -> [Float]? = { _ in [1, 0, 0] }
    ) -> CommandCore {
        CommandCore(
            engines: [MockEngine.fixed(.whisperKit, segments: [
                .init(start: 0, end: 2, text: "one"),
                .init(start: 2, end: 4, text: "two"),
            ], duration: 4)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            probe: .live(),
            diarizer: diarizer, enroller: enroller)
    }

    private func selection(_ ctx: String?) -> SelectionRequest {
        SelectionRequest(
            profileName: "balanced", backendOverride: nil, modelOverride: nil,
            requestedLanguage: "en", contextDir: ctx)
    }

    @Test func `An enrolled voice labels its turns by name, strangers stay ordinal`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        // A context dir with only voices/Alice.wav (no context.json).
        let voicesDir = dir.appendingPathComponent("ctx/voices")
        try FileManager.default.createDirectory(at: voicesDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: voicesDir.appendingPathComponent("Alice.wav").path, contents: Data([0]))

        // enroller returns [1,0,0] for Alice; the diarizer reports raw-A with a
        // matching embedding and raw-B orthogonal → post-hoc identify maps
        // raw-A→Alice, raw-B stays a stranger.
        let core = core(in: dir, diarizer: { _ in
            DiarizationOutput(
                turns: [
                    SpeakerTurn(speaker: "raw-A", start: 0, end: 2),
                    SpeakerTurn(speaker: "raw-B", start: 2, end: 4),
                ],
                embeddings: ["raw-A": [1, 0, 0], "raw-B": [0, 1, 0]])
        })
        let outcome = try await core.transcribe(
            audioPath: audio, selection: selection(dir.appendingPathComponent("ctx").path),
            formatName: "srt", outputPath: dir.appendingPathComponent("o.srt").path, diarize: true)
        let srt = try String(contentsOfFile: outcome.outputPath, encoding: .utf8)
        #expect(srt.contains("[Alice] one"))
        #expect(srt.contains("[SPEAKER_1] two"))
        #expect(outcome.explanation.contains("voices: 1/1 enrolled, 1 name(s) matched across 1 diarized speaker(s)"))
    }

    @Test func `Two raw speakers collapsing onto one name is disclosed, not hidden`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let voicesDir = dir.appendingPathComponent("ctx/voices")
        try FileManager.default.createDirectory(at: voicesDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: voicesDir.appendingPathComponent("Alice.wav").path, contents: Data([0]))
        // enroller returns [1,0,0]; BOTH raw ids sit within threshold of Alice.
        let core = core(in: dir, diarizer: { _ in
            DiarizationOutput(
                turns: [
                    SpeakerTurn(speaker: "raw-A", start: 0, end: 2),
                    SpeakerTurn(speaker: "raw-B", start: 2, end: 4),
                ],
                embeddings: ["raw-A": [1, 0, 0], "raw-B": [0.98, 0.2, 0]])  // both ≈ Alice
        }, enroller: { _ in [1, 0, 0] })
        let outcome = try await core.transcribe(
            audioPath: audio, selection: selection(dir.appendingPathComponent("ctx").path),
            formatName: "srt", outputPath: dir.appendingPathComponent("o.srt").path, diarize: true)
        // 1 name matched, but across 2 diarized speakers — the collapse is visible.
        #expect(outcome.explanation.contains("1 name(s) matched across 2 diarized speaker(s)"))
    }

    @Test func `No voices folder is pure diarization`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let core = core(in: dir, diarizer: { _ in
            DiarizationOutput(
                turns: [SpeakerTurn(speaker: "raw", start: 0, end: 4)],
                embeddings: ["raw": [1, 0, 0]])
        }, enroller: { _ in
            Issue.record("enroller must not run without voices/")
            return nil
        })
        let outcome = try await core.transcribe(
            audioPath: audio, selection: selection(nil), formatName: "srt",
            outputPath: dir.appendingPathComponent("o.srt").path, diarize: true)
        let srt = try String(contentsOfFile: outcome.outputPath, encoding: .utf8)
        #expect(srt.contains("[SPEAKER_1]"))
        #expect(!outcome.explanation.contains("voices:"))
    }
}

// #26: voices/ is reserved — discovered as enrollment, never parsed / ignored.
struct VoicesContextTests {
    @Test func `voices folder is collected and kept out of ignored files`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let voices = dir.appendingPathComponent("voices")
        try FileManager.default.createDirectory(at: voices, withIntermediateDirectories: true)
        for n in ["Bob.wav", "Alice.m4a", "notes.txt"] {  // notes.txt is a stray, not a voice
            FileManager.default.createFile(atPath: voices.appendingPathComponent(n).path, contents: Data([0]))
        }
        // a term list at top level to prove voices don't disturb parsing
        FileManager.default.createFile(atPath: dir.appendingPathComponent("terms.txt").path, contents: Data("hello\n".utf8))

        let loaded = try ContextLoader.load(directory: dir)
        #expect(loaded.voices.map(\.label) == ["Alice", "Bob"])  // sorted, stems only, .txt excluded
        #expect(!loaded.ignoredFiles.contains("voices"))
        #expect(loaded.termListTerms == ["hello"])  // top-level term list still parsed
    }
}


// #26: post-hoc identification — the pure embedding-match core.
struct SpeakerIdentifierTests {
    @Test func `Closest enrolled name within threshold wins; strangers stay unmapped`() {
        let embeddings = [
            "raw-A": [Float(1), 0, 0],   // == Alice direction
            "raw-B": [Float(0), 1, 0],   // orthogonal to both enrolled
        ]
        let enrolled = [(name: "Alice", embedding: [Float(1), 0, 0])]
        let map = SpeakerIdentifier.resolve(embeddings: embeddings, enrolled: enrolled)
        #expect(map == ["raw-A": "Alice"])  // raw-B distance 1.0 ≥ 0.65 → unmapped
    }

    @Test func `No enrolled voices maps nothing`() {
        #expect(SpeakerIdentifier.resolve(
            embeddings: ["x": [1, 0]], enrolled: []) == [:])
    }

    @Test func `Cosine distance: identical is 0, orthogonal is 1, zero-vector is max`() {
        #expect(SpeakerIdentifier.cosineDistance([1, 2, 3], [1, 2, 3]) < 1e-6)  // Float：≈0，非精確 0
        #expect(abs(SpeakerIdentifier.cosineDistance([1, 0], [0, 1]) - 1) < 1e-6)
        #expect(SpeakerIdentifier.cosineDistance([0, 0], [1, 1]) == 2)  // never spuriously matches
        #expect(SpeakerIdentifier.cosineDistance([1, 2], [1, 2, 3]) == 2)  // size mismatch
    }

    @Test func `Nearest of several enrolled voices wins`() {
        let embeddings = ["raw": [Float(0.9), 0.1, 0]]
        let enrolled = [
            (name: "Bob", embedding: [Float(0), 1, 0]),      // far
            (name: "Alice", embedding: [Float(1), 0, 0]),    // near
        ]
        #expect(SpeakerIdentifier.resolve(embeddings: embeddings, enrolled: enrolled) == ["raw": "Alice"])
    }
}
