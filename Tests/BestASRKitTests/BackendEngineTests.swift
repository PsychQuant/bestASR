import Foundation
import Testing
@testable import BestASRKit

struct WhisperKitEngineTests {
    @Test func `WhisperKit is always available on a supported host`() async {
        #expect(await WhisperKitEngine().isAvailable() == true)
    }

    @Test func `Registry model names map to WhisperKit search names`() {
        #expect(WhisperKitEngine.whisperKitModelName(for: "tiny") == "tiny")
        #expect(WhisperKitEngine.whisperKitModelName(for: "large-v3") == "large-v3")
        #expect(WhisperKitEngine.whisperKitModelName(for: "large-v3-turbo") == "large-v3_turbo")
    }
}

struct WhisperCppEngineTests {
    @Test func `Missing whisper-cli binary reports unavailable, not an error`() async {
        let engine = WhisperCppEngine(binaryPathOverride: "/nonexistent/whisper-cli")
        #expect(await engine.isAvailable() == false)
    }

    @Test func `Model file names follow the ggml distribution convention`() {
        #expect(
            WhisperCppEngine.modelFileName(model: "small", quantization: "q5_0")
                == "ggml-small-q5_0.bin"
        )
    }

    @Test func `whisper-cli JSON output parses into millisecond-scaled segments`() throws {
        let json = """
            {
              "result": { "language": "en" },
              "transcription": [
                { "offsets": { "from": 0, "to": 2500 }, "text": " hello world" },
                { "offsets": { "from": 2500, "to": 4000 }, "text": " again" }
              ]
            }
            """
        let raw = try WhisperCppEngine.parseOutput(Data(json.utf8), backend: "whisper.cpp")
        #expect(raw.segments.count == 2)
        #expect(raw.segments[0].start == 0.0)
        #expect(raw.segments[0].end == 2.5)
        #expect(raw.segments[0].text == " hello world")
        #expect(raw.language == "en")
    }

    @Test func `Malformed whisper-cli JSON is a typed transcription error`() {
        #expect(throws: TranscriptionError.self) {
            _ = try WhisperCppEngine.parseOutput(Data("not json".utf8), backend: "whisper.cpp")
        }
    }

    @Test func `Transcribing without the binary is a typed error with install guidance`() async {
        let engine = WhisperCppEngine(binaryPathOverride: "/nonexistent/whisper-cli")
        do {
            _ = try await engine.transcribe(
                audioPath: "clip.wav",
                options: TranscribeOptions(model: "small", quantization: "q5_0")
            )
            Issue.record("expected transcribe to throw")
        } catch let error as TranscriptionError {
            #expect(error.message.contains("brew install whisper-cpp"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
