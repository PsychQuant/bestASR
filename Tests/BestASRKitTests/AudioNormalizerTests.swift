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

}
