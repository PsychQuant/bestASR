import AVFoundation
import Foundation
import Testing
@testable import BestASRKit

/// AudioNormalizer contract (#36): engines only ever see 16 kHz mono input.
/// Long compressed files fed straight to WhisperKit exercised its broken
/// long-file resample path and produced garbage with exit 0 — the normalizer
/// guarantees that path is never reached.
struct AudioNormalizerTests {
    let options = TranscribeOptions(model: "small", quantization: "q5_1", language: "en")

    @Test func `Already 16 kHz mono audio passes through untouched`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try makeWavFile(in: dir, seconds: 1.0)

        let normalized = try AudioNormalizer.normalize(audioPath: path)

        #expect(normalized.path == path)
        #expect(normalized.isTemporary == false)
    }

    @Test func `44_1 kHz stereo audio converts to a temporary 16 kHz mono file`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A 440 Hz tone, not silence: the original failure emitted format-valid
        // output whose CONTENT was gone, so the assertion must cover both.
        let path = try makeWavFile(
            in: dir, seconds: 2.0, sampleRate: 44100, channels: 2, toneHz: 440)

        let normalized = try AudioNormalizer.normalize(audioPath: path)
        defer { normalized.cleanup() }

        #expect(normalized.path != path)
        #expect(normalized.isTemporary == true)
        let converted = try AVAudioFile(
            forReading: URL(fileURLWithPath: normalized.path))
        #expect(converted.fileFormat.sampleRate == 16000)
        #expect(converted.fileFormat.channelCount == 1)
        // Duration must survive conversion (the failure mode being fixed lost
        // almost all content, not a few priming frames).
        let duration = Double(converted.length) / converted.fileFormat.sampleRate
        #expect(abs(duration - 2.0) < 0.05)
        // Content must survive too: the tone's amplitude stays near 0.5 after
        // stereo downmix + resampling. A zeroing converter fails here.
        let frames = AVAudioFrameCount(converted.length)
        let readBuffer = AVAudioPCMBuffer(
            pcmFormat: converted.processingFormat, frameCapacity: frames)!
        try converted.read(into: readBuffer)
        var peak: Float = 0
        if let data = readBuffer.floatChannelData {
            for frame in 0..<Int(readBuffer.frameLength) {
                peak = max(peak, abs(data[0][frame]))
            }
        }
        #expect(peak > 0.2)
    }

    @Test func `Sample rate alone triggers conversion`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try makeWavFile(in: dir, seconds: 1.0, sampleRate: 48000, channels: 1)

        let normalized = try AudioNormalizer.normalize(audioPath: path)
        defer { normalized.cleanup() }

        #expect(normalized.isTemporary == true)
        let converted = try AVAudioFile(
            forReading: URL(fileURLWithPath: normalized.path))
        #expect(converted.fileFormat.sampleRate == 16000)
        #expect(converted.fileFormat.channelCount == 1)
    }

    @Test func `cleanup removes the temporary file but never the original`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let stereo = try makeWavFile(
            in: dir, seconds: 1.0, name: "stereo.wav", sampleRate: 44100, channels: 2)
        let converted = try AudioNormalizer.normalize(audioPath: stereo)
        #expect(FileManager.default.fileExists(atPath: converted.path))
        converted.cleanup()
        #expect(!FileManager.default.fileExists(atPath: converted.path))

        let mono = try makeWavFile(in: dir, seconds: 1.0, name: "mono.wav")
        let passthrough = try AudioNormalizer.normalize(audioPath: mono)
        passthrough.cleanup()
        #expect(FileManager.default.fileExists(atPath: mono))
    }

    @Test func `Unreadable input passes through so the engine keeps its error surface`() throws {
        // The CLI already fail-louds unreadable files via AudioProber before
        // any engine runs; at this seam a probe failure defers to the
        // engine's established error reporting instead of replacing it.
        let normalized = try AudioNormalizer.normalize(audioPath: "/nonexistent/clip.wav")
        #expect(normalized.path == "/nonexistent/clip.wav")
        #expect(normalized.isTemporary == false)
    }

    @Test func `Engine seam feeds the engine 16 kHz mono for non-conforming input`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try makeWavFile(in: dir, seconds: 1.0, sampleRate: 44100, channels: 2)

        // Spy engine reports what it actually received via the transcript text.
        let engine = MockEngine(id: .whisperKit, available: true) { received, _ in
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: received))
            let stamp =
                "\(received)|\(Int(file.fileFormat.sampleRate))|\(file.fileFormat.channelCount)"
            return RawTranscription(
                segments: [.init(start: 0, end: 1, text: stamp)],
                language: nil, duration: nil)
        }

        let transcript = try await engine.transcribe(audioPath: path, options: options)
        let parts = transcript.text.split(separator: "|").map(String.init)

        try #require(parts.count == 3)
        #expect(parts[0] != path)
        #expect(parts[1] == "16000")
        #expect(parts[2] == "1")
        // The temporary file is cleaned up once transcription returns.
        #expect(!FileManager.default.fileExists(atPath: parts[0]))
    }

    @Test func `Engine seam passes conforming audio through with the original path`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try makeWavFile(in: dir, seconds: 1.0)

        let engine = MockEngine(id: .whisperKit, available: true) { received, _ in
            RawTranscription(
                segments: [.init(start: 0, end: 1, text: received)],
                language: nil, duration: nil)
        }

        let transcript = try await engine.transcribe(audioPath: path, options: options)
        #expect(transcript.text == path)
    }

    @Test func `A 16k mono compressed container is still normalized to WAV`() throws {
        // #42: the passthrough test must include the CONTAINER — whisper.cpp
        // only eats WAV, so a 16k mono m4a passing through unchanged fails
        // downstream even though rate/channels match.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let m4a = dir.appendingPathComponent("clip.m4a")
        // Scope the writer so AVAudioFile finalizes the container before
        // normalize() reads it back.
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            let file = try AVAudioFile(
                forWriting: m4a,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1,
                ])
            let frames = AVAudioFrameCount(16000)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            try file.write(from: buffer)
        }

        let normalized = try AudioNormalizer.normalize(audioPath: m4a.path)
        defer { normalized.cleanup() }
        #expect(normalized.isTemporary)  // converted, not passed through
        #expect(normalized.path.hasSuffix(".wav"))
    }

    @Test func `A 16k mono PCM in a non-WAV container (caf) is still normalized`() throws {
        // #42 verify HIGH: LinearPCM is an ENCODING property — a .caf holds
        // LinearPCM too, but whisper-cli parses only RIFF/WAV. Container
        // must be WAV for passthrough.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let caf = dir.appendingPathComponent("clip.caf")
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            let file = try AVAudioFile(
                forWriting: caf,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1,
                ])
            let frames = AVAudioFrameCount(16000)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            try file.write(from: buffer)
        }
        let normalized = try AudioNormalizer.normalize(audioPath: caf.path)
        defer { normalized.cleanup() }
        #expect(normalized.isTemporary)
        #expect(normalized.path.hasSuffix(".wav"))
    }

    @Test func `A 16k mono WAV still passes through untouched`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = try makeWavFile(in: dir)
        let normalized = try AudioNormalizer.normalize(audioPath: wav)
        #expect(!normalized.isTemporary)
        #expect(normalized.path == wav)
    }

    @Test func `A converter failure surfaces as a thrown error, never a silent passthrough`() throws {
        // #42 gap 2: the fail-loud chain finally has an injectable seam.
        struct Boom: Error {}
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = try makeWavFile(in: dir, name: "hi.wav", sampleRate: 44100, channels: 2)
        #expect(throws: (any Error).self) {
            _ = try AudioNormalizer.normalize(audioPath: wav, converter: { _, _ in throw Boom() })
        }
    }


    @Test func `Stale normalized temp files are swept, fresh ones survive`() throws {
        // #43: defer-based cleanup cannot run on SIGKILL/OOM — 160MB-class
        // residues accumulate monotonically without a sweep.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stale = dir.appendingPathComponent("bestasr-normalized-STALE.wav")
        let fresh = dir.appendingPathComponent("bestasr-normalized-FRESH.wav")
        let foreign = dir.appendingPathComponent("unrelated.wav")
        for f in [stale, fresh, foreign] {
            FileManager.default.createFile(atPath: f.path, contents: Data("x".utf8))
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -25 * 3600)],
            ofItemAtPath: stale.path)

        AudioNormalizer.sweepStaleTemporaries(in: dir, olderThan: 24 * 3600)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: foreign.path))  // never touch non-ours
    }

    @Test func `cleanup on an already-removed file is a silent no-op`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ghost = dir.appendingPathComponent("bestasr-normalized-GONE.wav")
        FileManager.default.createFile(atPath: ghost.path, contents: nil)
        let normalized = AudioNormalizer.NormalizedAudio(path: ghost.path, isTemporary: true)
        try FileManager.default.removeItem(at: ghost)
        normalized.cleanup()  // already gone is not a failure — early return, no warning
    }

    @Test func `cleanup failure on an existing file warns instead of trapping`() throws {
        // Cluster-verify MEDIUM: drive the ACTUAL catch branch — the file
        // exists but removeItem throws (read-only parent directory).
        let dir = try makeTempDir()
        let parent = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let stuck = parent.appendingPathComponent("bestasr-normalized-STUCK.wav")
        FileManager.default.createFile(atPath: stuck.path, contents: Data("x".utf8))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: parent.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let normalized = AudioNormalizer.NormalizedAudio(path: stuck.path, isTemporary: true)
        normalized.cleanup()  // must warn on stderr, never trap
        #expect(FileManager.default.fileExists(atPath: stuck.path))  // delete really failed
    }


    // MARK: - #40 truncated-container characterization (probe-arbitrated 2026-07-07)
    //
    // Live probes settled the #36 reviewer disagreement ("overstated length:
    // 0-frame reads vs throw"):
    //   WAV:  AVAudioFile.length tracks the ACTUAL byte count, not the header
    //         declaration — the overstated-length case cannot arise.
    //   m4a with moov intact (AVAudioFile writes moov FIRST, mdat last —
    //         verified by atom offsets): truncation removes mdat, open still
    //         succeeds, length stays at the FULL declared value, and the FIRST
    //         read throws (-50) — the fail-loud read-error branch inside
    //         convert() catches it. No benign-EOF whitelist is warranted: a
    //         throwing read on a compressed container means a damaged file,
    //         never a normal EOF.
    //   m4a with moov damaged/missing: open itself throws → normalize()
    //         passes through by design (AudioProber upstream owns the
    //         fail-loud for unreadable inputs on every CLI path).
    // NOTE: the truncated-m4a test depends on the platform writer placing
    // mdat last (implementation detail, not API contract). If a future OS
    // interleaves mdat, open() would fail → passthrough → the #expect(throws:)
    // fails, flagging that this characterization needs re-probing.

    @Test func `A truncated WAV reports its actual frame count, not the header declaration`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = try makeWavFile(in: dir, seconds: 10)
        let data = try Data(contentsOf: URL(fileURLWithPath: wav))
        let trunc = dir.appendingPathComponent("trunc.wav")
        try data.prefix(data.count / 2).write(to: trunc)

        let file = try AVAudioFile(forReading: trunc)
        #expect(file.length < 160000 / 2 + 4096)  // tracks real bytes, not header
    }

    @Test func `A truncated m4a fails loud through the convert read-error branch`() throws {
        // Also closes the #42 verify MEDIUM gap: this is a REAL file driving
        // the fail-loud chain inside convert() — no injected converter.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let m4a = dir.appendingPathComponent("full.m4a")
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            let file = try AVAudioFile(
                forWriting: m4a,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1,
                ])
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160000)!
            buffer.frameLength = 160000
            try file.write(from: buffer)
        }
        let data = try Data(contentsOf: m4a)
        let trunc = dir.appendingPathComponent("trunc.m4a")
        try data.prefix(Int(Double(data.count) * 0.6)).write(to: trunc)

        #expect(throws: (any Error).self) {
            _ = try AudioNormalizer.normalize(audioPath: trunc.path)
        }
    }

}
