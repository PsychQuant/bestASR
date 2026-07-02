import Foundation
import Testing
import WhisperKit
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

struct PromptForwardingTests {
    @Test func `whisper-cli arguments carry the prompt when present`() {
        let args = WhisperCppEngine.makeArguments(
            modelPath: "/m/ggml-small-q5_0.bin", audioPath: "clip.wav",
            outputBase: "/tmp/out", language: "zh", prompt: "鄭澈, Che, CoreML")
        #expect(args.contains("--prompt"))
        let idx = args.firstIndex(of: "--prompt")!
        #expect(args[idx + 1] == "鄭澈, Che, CoreML")
    }

    @Test func `Absent prompt adds nothing to the whisper-cli invocation`() {
        let args = WhisperCppEngine.makeArguments(
            modelPath: "/m/x.bin", audioPath: "clip.wav",
            outputBase: "/tmp/out", language: nil, prompt: nil)
        #expect(!args.contains("--prompt"))
    }

    @Test func `WhisperKit prompt tokens are clamped under the 224 window`() {
        let big = Array(0..<500)
        let clamped = WhisperKitEngine.clampedPromptTokens(big)
        #expect(clamped.count == 224)
        #expect(clamped.last == 499)  // suffix keeps the most recent tokens
        #expect(WhisperKitEngine.clampedPromptTokens([1, 2, 3]) == [1, 2, 3])
    }

    @Test func `Options prompt flows through the engine seam`() async throws {
        // MockEngine's raw closure sees the same options the caller passed —
        // the transcribe template method forwards prompt untouched.
        let engine = MockEngine(id: .whisperKit, available: true) { _, options in
            #expect(options.prompt == "鄭澈, CoreML")
            return RawTranscription(
                segments: [.init(start: 0, end: 1, text: "hi")], language: "zh", duration: 1)
        }
        _ = try await engine.transcribe(
            audioPath: "clip.wav",
            options: TranscribeOptions(
                model: "tiny", quantization: "default", language: "zh", prompt: "鄭澈, CoreML")
        )
    }
}

struct DecodeOptionsTests {
    @Test func `Special tokens are always skipped — the #6 regression lock`() {
        let options = WhisperKitEngine.makeDecodeOptions(language: "en", promptTokens: nil)
        #expect(options.skipSpecialTokens == true)
        #expect(options.language == "en")
        #expect(options.detectLanguage == false)
    }

    @Test func `Prompt tokens are prepended when present; auto language switches on detection`() {
        let with = WhisperKitEngine.makeDecodeOptions(language: nil, promptTokens: [1, 2, 3])
        #expect(with.skipSpecialTokens == true)
        #expect(with.promptTokens == [1, 2, 3])
        #expect(with.detectLanguage == true)
    }

    @Test func `Nil and empty prompt tokens both leave the decode options prompt-free`() {
        // Empty non-nil ≠ nil in WhisperKit 0.18 (stray <|startofprev|> +
        // disabled prefill cache) — the factory must treat both as no-prompt.
        #expect(WhisperKitEngine.makeDecodeOptions(language: "en", promptTokens: nil).promptTokens == nil)
        #expect(WhisperKitEngine.makeDecodeOptions(language: "en", promptTokens: []).promptTokens == nil)
    }
}
