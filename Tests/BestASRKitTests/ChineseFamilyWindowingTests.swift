import AVFoundation
import Foundation
import Testing

@testable import BestASRKit

/// #106 — fixed-window slicing for SenseVoice-class backends: long audio is
/// windowed at the backend's per-call ceiling with real window timestamps;
/// short audio keeps the untouched direct path.
struct ChineseFamilyWindowingTests {
    /// Sequential-use recorder; the engine's window loop awaits each call.
    final class RecordingPipeline: TextTranscribing, @unchecked Sendable {
        private(set) var paths: [String] = []
        func transcribe(audioPath: String, language: String?) async throws -> String {
            paths.append(audioPath)
            return "seg\(paths.count)"
        }
    }

    /// Writes `seconds` of 16 kHz mono silence as a wav (what the engine
    /// seam's normalizer guarantees production inputs look like).
    private func makeWav(seconds: Double) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("windowing-test-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(
            forWriting: url, settings: settings,
            commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * 16000.0)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: frames)
        else { throw BestASRError.runtime("buffer allocation failed") }
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url.path
    }

    private func engine(_ pipe: RecordingPipeline) -> ChineseFamilyEngine {
        ChineseFamilyEngine(
            id: .fluidSenseVoice,
            probeDuration: { try AudioProber.probe(path: $0, requestedLanguage: nil).duration ?? 0 },
            pipelineFactory: { _ in pipe },
            windowLimit: (max: 30.0, min: 0.2))
    }

    @Test func `Long audio is sliced into 30s windows with real timestamps`() async throws {
        let path = try makeWav(seconds: 75)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pipe = RecordingPipeline()
        let raw = try await engine(pipe).transcribeRaw(
            audioPath: path, options: TranscribeOptions(model: "small", quantization: "default"))
        #expect(pipe.paths.count == 3)  // 30 + 30 + 15
        #expect(raw.segments.count == 3)
        #expect(raw.segments[0].start == 0 && raw.segments[0].end == 30)
        #expect(raw.segments[1].start == 30 && raw.segments[1].end == 60)
        #expect(raw.segments[2].start == 60 && abs(raw.segments[2].end - 75) < 0.01)
        #expect(raw.segments.map(\.text) == ["seg1", "seg2", "seg3"])
        // every slice was a temporary distinct from the input, and got cleaned up
        for slicePath in pipe.paths {
            #expect(slicePath != path)
            #expect(!FileManager.default.fileExists(atPath: slicePath))
        }
    }

    @Test func `Short audio keeps the direct single-call path`() async throws {
        let path = try makeWav(seconds: 10)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pipe = RecordingPipeline()
        let raw = try await engine(pipe).transcribeRaw(
            audioPath: path, options: TranscribeOptions(model: "small", quantization: "default"))
        #expect(pipe.paths == [path])  // untouched original, no temp slice
        #expect(raw.segments.count == 1)
        #expect(raw.segments[0].start == 0 && abs(raw.segments[0].end - 10) < 0.01)
    }

    @Test func `A sub-floor tail window is dropped, not sent to the backend`() async throws {
        let path = try makeWav(seconds: 30.1)  // 30s window + 0.1s (< 0.2s floor)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pipe = RecordingPipeline()
        let raw = try await engine(pipe).transcribeRaw(
            audioPath: path, options: TranscribeOptions(model: "small", quantization: "default"))
        #expect(pipe.paths.count == 1)
        #expect(raw.segments.count == 1)
        #expect(raw.segments[0].end == 30)
    }
}
