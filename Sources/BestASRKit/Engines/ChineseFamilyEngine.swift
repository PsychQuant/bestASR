import FluidAudio
import Foundation

/// Chinese-family FluidAudio engines (#50, spec chinese-asr-engines):
/// Paraformer (zh-focused large) and SenseVoice (small, multilingual with
/// automatic language detection) — the candidate pool's answer to "Chinese
/// requests only ever see Whisper". Zero new dependencies: both managers
/// ship inside the exact-pinned FluidAudio release, same as Parakeet (#35).
///
/// API mapping (FluidAudio 0.15.4 → BestASRKit):
///
/// | FluidAudio                                    | here                       |
/// |-----------------------------------------------|----------------------------|
/// | `ParaformerManager.load(precision:)`          | paraformer pipeline factory|
/// | `SenseVoiceManager.load(precision:)`          | sensevoice pipeline factory|
/// | `manager.transcribe(audioURL:) -> String`     | `TextTranscribing`         |
///
/// Both managers return plain text — no confidence, no token timings — so
/// the raw transcription is one full-duration segment with nil confidence
/// (design D2: no fabricated sub-segment timings; timed-cue formats carry a
/// single cue, full-text benchmark error rates are unaffected). SenseVoice
/// runs with automatic language detection: FluidAudio does not export the
/// per-language embed-index table, and a wrong guess would silently degrade
/// quality (design D3).

/// The slice of FluidAudio these engines consume — injectable for tests.
protocol TextTranscribing: Sendable {
    func transcribe(audioPath: String, language: String?) async throws -> String
}

struct FluidAudioParaformerPipeline: TextTranscribing {
    let manager: ParaformerManager

    func transcribe(audioPath: String, language: String?) async throws -> String {
        try await manager.transcribe(audioURL: URL(fileURLWithPath: audioPath))
    }
}

struct FluidAudioSenseVoicePipeline: TextTranscribing {
    let manager: SenseVoiceManager

    func transcribe(audioPath: String, language: String?) async throws -> String {
        // Auto language detection (design D3) — the manager was built with
        // the upstream default language constant.
        try await manager.transcribe(audioURL: URL(fileURLWithPath: audioPath))
    }
}

/// One parameterized conformer covers both text-only Chinese families —
/// the backend id and pipeline factory are the only differences.
public struct ChineseFamilyEngine: Engine {
    public let id: BackendID

    let probeDuration: @Sendable (String) throws -> TimeInterval
    let pipelineFactory: @Sendable (String) async throws -> any TextTranscribing
    let pipelines = CreateOnceStore<any TextTranscribing>()
    /// #106: per-call sample window of a fixed-window backend, in seconds
    /// (max) and the backend's floor (min). nil = the backend takes whole
    /// files (paraformer today). SenseVoice: 0.2–30 s per call — longer
    /// input hard-fails inside the CoreML graph, so the engine slices.
    let windowLimit: (max: Double, min: Double)?

    init(
        id: BackendID,
        probeDuration: @escaping @Sendable (String) throws -> TimeInterval,
        pipelineFactory: @escaping @Sendable (String) async throws -> any TextTranscribing,
        windowLimit: (max: Double, min: Double)? = nil
    ) {
        self.id = id
        self.probeDuration = probeDuration
        self.pipelineFactory = pipelineFactory
        self.windowLimit = windowLimit
    }

    public static func paraformer() -> ChineseFamilyEngine {
        ChineseFamilyEngine(
            id: .fluidParaformer,
            probeDuration: Self.probedDuration,
            pipelineFactory: { _ in
                FluidAudioParaformerPipeline(manager: try await ParaformerManager.load())
            })
    }

    public static func sensevoice() -> ChineseFamilyEngine {
        ChineseFamilyEngine(
            id: .fluidSenseVoice,
            probeDuration: Self.probedDuration,
            pipelineFactory: { _ in
                FluidAudioSenseVoicePipeline(manager: try await SenseVoiceManager.load())
            },
            // #106: SenseVoice's CoreML graph accepts 3 200–480 000 samples
            // (0.2–30 s at the 16 kHz the engine seam guarantees) per call.
            windowLimit: (max: 30.0, min: 0.2))
    }

    private static func probedDuration(_ audioPath: String) throws -> TimeInterval {
        try AudioProber.probe(path: audioPath, requestedLanguage: nil).duration ?? 0
    }

    public func isAvailable() async -> Bool {
        true
    }

    public func transcribeRaw(
        audioPath: String, options: TranscribeOptions
    ) async throws -> RawTranscription {
        let pipe: any TextTranscribing
        do {
            let factory = pipelineFactory
            pipe = try await pipelines.value(for: options.model) {
                try await factory(options.model)
            }
        } catch {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "failed to load model '\(options.model)': \(error.localizedDescription)",
                underlying: error
            )
        }

        let duration = (try? probeDuration(audioPath)) ?? 0

        // #106: a fixed-window backend never sees more than its per-call
        // ceiling — longer input is sliced into windows, each transcribed
        // separately, each becoming a segment with its REAL window times
        // (an improvement over the former single full-duration cue).
        if let windowLimit, duration > windowLimit.max {
            let windows: [AudioWindower.Window]
            do {
                windows = try AudioWindower.slice(
                    audioPath: audioPath,
                    maxSeconds: windowLimit.max, minSeconds: windowLimit.min)
            } catch {
                throw TranscriptionError(
                    backend: id.rawValue,
                    message: "windowing \(audioPath) failed: \(error.localizedDescription)",
                    underlying: error
                )
            }
            defer { AudioWindower.cleanup(windows) }

            var segments: [RawTranscription.RawSegment] = []
            for window in windows {
                let text: String
                do {
                    text = try await pipe.transcribe(
                        audioPath: window.path, language: options.language)
                } catch {
                    throw TranscriptionError(
                        backend: id.rawValue,
                        message: String(
                            format: "%@ (window %.1f–%.1fs): %@",
                            audioPath, window.start, window.end, error.localizedDescription),
                        underlying: error
                    )
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(
                        .init(
                            start: window.start, end: window.end,
                            text: trimmed, confidence: nil))
                }
            }
            return RawTranscription(
                segments: segments, language: options.language, duration: duration)
        }

        let text: String
        do {
            text = try await pipe.transcribe(audioPath: audioPath, language: options.language)
        } catch {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "\(audioPath): \(error.localizedDescription)",
                underlying: error
            )
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments: [RawTranscription.RawSegment] =
            trimmed.isEmpty
            ? []
            : [.init(start: 0, end: duration, text: trimmed, confidence: nil)]
        return RawTranscription(
            segments: segments, language: options.language, duration: duration)
    }
}
