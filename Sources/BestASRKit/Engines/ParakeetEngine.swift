import AVFoundation
import FluidAudio
import Foundation

/// FluidAudio Parakeet backend (#35, spec parakeet-engine) — the first
/// non-Whisper family in the competition pool, zero new dependencies
/// (FluidAudio 0.15.4 is already exact-pinned for diarization, #25).
///
/// API mapping (task 1.1 spike, FluidAudio 0.15.4 → BestASRKit):
///
/// | FluidAudio                                              | here                          |
/// |---------------------------------------------------------|-------------------------------|
/// | `AsrModels.downloadAndLoad(version: .v3)`                | pipeline factory (lazy, #7)   |
/// | `AsrManager(config: .default, models:)`                  | held by the production adapter|
/// | `manager.transcribe(URL, decoderState:, language:)`      | `transcribe(audioPath:language:)` |
/// | `ASRResult.text / .confidence / .duration`               | `ParakeetOutput` fields       |
/// | `ASRResult.tokenTimings: [TokenTiming]?`                 | `ParakeetOutput.tokenTimings` |
/// | `Language(rawValue:)` (v3 script-aware hint, euro set)   | `options.language` best-effort|
///
/// `AsrManager.transcribe(URL, ...)` handles long files itself (disk-backed
/// chunked processing, constant memory) — no extra chunking layer here. The
/// engine seam already guarantees 16 kHz mono input (#36 AudioNormalizer),
/// and FluidAudio resamples defensively on top; both paths are cheap for
/// conforming input.
///
/// Segment shaping: Parakeet reports token-level timings, not segments. The
/// mapper splits at inter-token gaps > `segmentGapSeconds` so SRT cues track
/// natural pauses; with no timings it degrades to one full-text segment.

/// Backend-neutral slice of a Parakeet transcription — the seam type (#9
/// discipline: tests spy on this without loading CoreML models).
public struct ParakeetOutput: Sendable {
    public struct Timing: Sendable {
        public let token: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval

        public init(token: String, startTime: TimeInterval, endTime: TimeInterval) {
            self.token = token
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    public let text: String
    public let confidence: Double
    public let duration: TimeInterval
    public let tokenTimings: [Timing]?

    public init(
        text: String, confidence: Double, duration: TimeInterval, tokenTimings: [Timing]?
    ) {
        self.text = text
        self.confidence = confidence
        self.duration = duration
        self.tokenTimings = tokenTimings
    }
}

/// The slice of FluidAudio the engine consumes — injectable for tests.
protocol ParakeetTranscribing: Sendable {
    func transcribe(audioPath: String, language: String?) async throws -> ParakeetOutput
}

/// Production adapter: owns the loaded AsrManager. A fresh TdtDecoderState
/// per call keeps files independent (stateless per transcription).
///
/// Concurrency (#53 item 3): FluidAudio's AsrManager is not documented as
/// thread-safe, and actor-izing it is upstream's call. bestASR's CLI drives
/// every transcription sequentially (one engine call at a time per process),
/// which is the safety assumption this adapter relies on — a future parallel
/// benchmark runner must serialize per-pipeline access before fanning out.
struct FluidAudioParakeetPipeline: ParakeetTranscribing {
    let manager: AsrManager

    func transcribe(audioPath: String, language: String?) async throws -> ParakeetOutput {
        var state = try TdtDecoderState()
        // v3 script-aware hint covers a European-language set; unknown codes
        // (zh, ja, …) resolve to nil and Parakeet decodes unhinted.
        let hint = language.flatMap { Language(rawValue: $0) }
        let result = try await manager.transcribe(
            URL(fileURLWithPath: audioPath), decoderState: &state, language: hint)
        return ParakeetOutput(
            text: result.text,
            confidence: Double(result.confidence),
            duration: result.duration,
            tokenTimings: result.tokenTimings?.map {
                .init(token: $0.token, startTime: $0.startTime, endTime: $0.endTime)
            }
        )
    }
}

/// FluidAudio Parakeet engine — third `Engine` conformer.
public struct ParakeetEngine: Engine {
    public let id: BackendID = .fluidParakeet

    /// Inter-token silence that starts a new raw segment.
    static let segmentGapSeconds: TimeInterval = 0.8

    public init() {
        self.init(pipelineFactory: { model in
            // Models download on first use (same posture as WhisperKit); the
            // pinned FluidAudio release manages weights + auto-recovery.
            // The grid's model key maps explicitly to a FluidAudio version —
            // a new grid row without a mapping fails loud instead of
            // silently loading v3 weights for it (#53 item 5).
            guard let version = Self.modelVersions[model] else {
                throw TranscriptionError(
                    backend: BackendID.fluidParakeet.rawValue,
                    message: "no FluidAudio model version mapped for grid model '\(model)'",
                    underlying: nil)
            }
            // #52 (spec weight-pinning): download and verify BEFORE load —
            // drifted weights must never reach CoreML compilation.
            let modelsDir = try await AsrModels.download(version: version)
            try WeightVerifier.verifyBundled(repo: "parakeet-tdt-0.6b-v3")
            let models = try await AsrModels.load(from: modelsDir, version: version)
            return FluidAudioParakeetPipeline(manager: AsrManager(config: .default, models: models))
        })
    }

    /// Grid model key → FluidAudio version (kept next to the factory so a
    /// grid addition and its mapping land in one diff).
    static let modelVersions: [String: AsrModelVersion] = ["0.6b-v3": .v3]

    /// Internal seam (#9): tests inject a spy keyed by model name.
    init(
        pipelineFactory: @escaping @Sendable (String) async throws -> any ParakeetTranscribing
    ) {
        self.pipelineFactory = pipelineFactory
    }

    let pipelineFactory: @Sendable (String) async throws -> any ParakeetTranscribing

    /// Per-instance pipeline cache (#7): the CoreML load happens once per
    /// model for the engine's lifetime.
    let pipelines = CreateOnceStore<any ParakeetTranscribing>()

    public func isAvailable() async -> Bool {
        true
    }

    public func transcribeRaw(
        audioPath: String, options: TranscribeOptions
    ) async throws -> RawTranscription {
        let pipe: any ParakeetTranscribing
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

        let output: ParakeetOutput
        do {
            output = try await pipe.transcribe(audioPath: audioPath, language: options.language)
        } catch {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "\(audioPath): \(error.localizedDescription)",
                underlying: error
            )
        }

        // Duration fallback (#69): FluidAudio 0.15.4 returns duration 0,
        // which collapses the #53 sanitizer's upper bound to a zero point —
        // every real timing gets distrusted and the SRT cue becomes
        // 00:00:00 --> 00:00:00. Never trust the upstream field alone: fall
        // back to the timings' own extent, then to the probed audio length.
        var repaired = output
        if repaired.duration <= 0 {
            let fallback = repaired.tokenTimings?.map(\.endTime).max()
                ?? (try? AudioProber.probe(path: audioPath, requestedLanguage: nil)
                    .duration).flatMap { $0 }
            if let fallback, fallback > 0 {
                repaired = ParakeetOutput(
                    text: repaired.text, confidence: repaired.confidence,
                    duration: fallback, tokenTimings: repaired.tokenTimings)
            }
        }
        return RawTranscription(
            segments: Self.segments(from: repaired),
            language: options.language,
            duration: repaired.duration
        )
    }

    /// Groups token timings into raw segments at natural pauses; degrades to
    /// one full-text segment when timings are absent — or when they
    /// reconstruct to nothing (all-whitespace tokens), so `output.text` is
    /// never silently dropped (#35 verify M1).
    static func segments(from output: ParakeetOutput) -> [RawTranscription.RawSegment] {
        func fullTextSegment() -> [RawTranscription.RawSegment] {
            let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [
                .init(start: 0, end: output.duration, text: text, confidence: output.confidence)
            ]
        }
        guard let rawTimings = output.tokenTimings, !rawTimings.isEmpty else {
            return fullTextSegment()
        }
        // Seam defense (#53 item 2): a misbehaving pipeline may emit
        // negative, past-duration, out-of-order, or inverted (end < start)
        // timings. Partially in-range pairs are clamped into 0...duration
        // and re-ordered; but an inverted RAW pair, or one that clamps to a
        // zero-length point entirely outside the audio, means the batch as a
        // whole cannot be trusted — dropping just those tokens would drop
        // their TEXT, so the whole batch falls back to the full-text single
        // segment instead. Text is never lost either way.
        let upperBound = max(output.duration, 0)
        var sanitized: [(index: Int, timing: ParakeetOutput.Timing)] = []
        for (index, t) in rawTimings.enumerated() {
            guard t.endTime >= t.startTime else { return fullTextSegment() }
            let start = min(max(t.startTime, 0), upperBound)
            let end = min(max(t.endTime, 0), upperBound)
            // A non-degenerate raw pair collapsing to a point means it lay
            // entirely outside 0...duration — the batch contradicts the
            // audio's own duration.
            if end == start && t.endTime > t.startTime { return fullTextSegment() }
            sanitized.append((index, .init(token: t.token, startTime: start, endTime: end)))
        }
        // Explicit (startTime, original index) tie-break: emission order is
        // preserved for simultaneous tokens without assuming sort stability
        // (Ranking.swift documents the same discipline).
        let timings = sanitized
            .sorted { ($0.timing.startTime, $0.index) < ($1.timing.startTime, $1.index) }
            .map(\.timing)
        guard !timings.isEmpty else { return fullTextSegment() }

        var segments: [RawTranscription.RawSegment] = []
        var groupTokens: [ParakeetOutput.Timing] = []

        func flush() {
            guard let first = groupTokens.first, let last = groupTokens.last else { return }
            var text = groupTokens.map(\.token).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                // Seam contract (#35 verify H1): Engine.transcribe joins
                // segment texts with NO separator — every segment after the
                // first carries its own leading space (as WhisperKit's do),
                // or pause boundaries would glue words together and inflate
                // this family's measured WER.
                if !segments.isEmpty { text = " " + text }
                segments.append(
                    .init(
                        start: first.startTime, end: last.endTime,
                        text: text, confidence: output.confidence))
            }
            groupTokens.removeAll()
        }

        for timing in timings {
            if let previous = groupTokens.last,
                timing.startTime - previous.endTime > segmentGapSeconds {
                flush()
            }
            groupTokens.append(timing)
        }
        flush()
        guard !segments.isEmpty else { return fullTextSegment() }
        return segments
    }
}
