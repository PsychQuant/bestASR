import Foundation
import Testing

@testable import BestASRKit

/// Minimal stand-in so the Chinese-family engine can be constructed; this test
/// only reads a declaration and never transcribes.
private struct InertTranscriber: TextTranscribing {
    func transcribe(audioPath: String, language: String?) async throws -> String { "" }
}

/// Every backend's prompt declaration, checked against what it actually does
/// (spec `Common engine interface`).
///
/// Declaring a capability does not make it true, and a declaration nobody
/// verifies is the same class of claim as the `injected (N)` line this whole
/// change exists to remove. So this asserts both halves: the value each engine
/// declares, and — structurally — that only the engines declaring support are
/// the ones whose source actually forwards `options.prompt` to a backend.
struct EngineCapabilityTests {
    static let engineSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/BestASRKit/Engines")

    /// The measured ceiling shared by both Whisper backends.
    ///
    /// `whisper-cli --help` states `--prompt PROMPT (max n_text_ctx/2 tokens)`,
    /// and Whisper's `n_text_ctx` is 448 — so 224. WhisperKit's own clamp uses
    /// the same number, independently arrived at, which is why a single third
    /// "limit unknown" case was not needed (design D1).
    static let whisperPromptLimit = 224

    @Test func `The Whisper-family backends declare support at the measured 224 ceiling`() {
        #expect(
            WhisperKitEngine().promptCapability == .supported(maxTokens: Self.whisperPromptLimit))
        #expect(
            WhisperCppEngine().promptCapability == .supported(maxTokens: Self.whisperPromptLimit))
    }

    @Test func `Backends that ignore conditioning text declare no support`() {
        #expect(ParakeetEngine().promptCapability == .unsupported)
        #expect(AppleSpeechEngine().promptCapability == .unsupported)
        #expect(
            ChineseFamilyEngine(
                id: .fluidParaformer,
                probeDuration: { _ in 1.0 },
                pipelineFactory: { _ in InertTranscriber() }
            ).promptCapability == .unsupported)
        #expect(
            ExternalProcessEngine(id: .mlxAudio, command: ["/bin/echo"]).promptCapability
                == .unsupported)
    }

    /// The declaration must match the code, not the author's intention.
    ///
    /// An engine that forwards `options.prompt` to its backend is claiming to
    /// use it; one that never mentions it cannot be. This compares the two sets
    /// and fails on either kind of drift — a backend that quietly starts using
    /// the prompt without declaring support, or one that declares support it
    /// does not act on.
    @Test func `Each declaration matches whether the source actually forwards the prompt`() throws {
        let declaredSupported = ["WhisperKitEngine", "WhisperCppEngine"]
        var actuallyForwards: [String] = []
        for name in [
            "WhisperKitEngine", "WhisperCppEngine", "ParakeetEngine",
            "AppleSpeechEngine", "ChineseFamilyEngine", "ExternalProcessEngine",
        ] {
            let source = try String(
                contentsOf: Self.engineSources.appendingPathComponent("\(name).swift"),
                encoding: .utf8)
            // Strip comments so prose about prompts is not mistaken for use.
            let code = source
                .replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"(?m)//.*$"#, with: " ", options: .regularExpression)
            if code.contains("options.prompt") { actuallyForwards.append(name) }
        }
        #expect(
            actuallyForwards.sorted() == declaredSupported.sorted(),
            """
            Prompt declaration and behavior disagree.
            Declares support: \(declaredSupported.sorted())
            Forwards options.prompt: \(actuallyForwards.sorted())
            An engine that started using the prompt must declare it, and one that
            declares support must act on it — that mismatch is the bug this
            change removes.
            """)
    }
}
