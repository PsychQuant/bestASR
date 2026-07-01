import Foundation
import Testing
@testable import BestASRKit

struct EngineTests {
    let options = TranscribeOptions(model: "small", quantization: "q5_0", language: "en")

    @Test func `Transcription normalizes segment order, ids, text, and duration`() async throws {
        // Raw segments arrive out of order; normalization must sort by start
        // and re-number ids from 1 (spec: Transcription returns a normalized Transcript).
        let engine = MockEngine.fixed(
            .whisperKit,
            segments: [
                .init(start: 1.0, end: 2.5, text: " world"),
                .init(start: 0.0, end: 1.0, text: "hello"),
            ],
            language: "en",
            duration: nil
        )
        let transcript = try await engine.transcribe(audioPath: "clip.wav", options: options)
        #expect(transcript.segments.map(\.id) == [1, 2])
        #expect(transcript.segments.map(\.start) == [0.0, 1.0])
        #expect(transcript.text == "hello world")
        #expect(transcript.backend == "whisperkit")
        #expect(transcript.model == "small")
        #expect(transcript.duration == 2.5)  // defaulted to the last segment's end
    }

    @Test func `Engine language falls back to the requested language`() async throws {
        let engine = MockEngine.fixed(.whisperCpp, language: nil)
        let transcript = try await engine.transcribe(
            audioPath: "clip.wav",
            options: TranscribeOptions(model: "tiny", quantization: "q5_0", language: "zh")
        )
        #expect(transcript.language == "zh")
    }

    @Test func `Backend failures are wrapped in a typed TranscriptionError`() async {
        let engine = MockEngine.failing(.whisperKit, message: "decode error")
        await #expect(throws: TranscriptionError.self) {
            _ = try await engine.transcribe(audioPath: "broken.wav", options: options)
        }
    }

    @Test func `Typed transcription errors pass through without double wrapping`() async {
        let typed = TranscriptionError(backend: "whisper.cpp", message: "model file missing")
        let engine = MockEngine(id: .whisperCpp, available: true) { _, _ in throw typed }
        do {
            _ = try await engine.transcribe(audioPath: "clip.wav", options: options)
            Issue.record("expected transcribe to throw")
        } catch let error as TranscriptionError {
            #expect(error.backend == "whisper.cpp")
            #expect(error.message == "model file missing")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func `Unavailable engine reports false without throwing`() async {
        let engine = MockEngine.fixed(.whisperCpp, available: false)
        #expect(await engine.isAvailable() == false)
    }

    @Test func `Protocol extension provides positive requirement estimates`() throws {
        let engine = MockEngine.fixed(.whisperKit)
        let req = try engine.estimateRequirements(model: "medium")
        #expect(req.memoryGB > 0)
    }
}
