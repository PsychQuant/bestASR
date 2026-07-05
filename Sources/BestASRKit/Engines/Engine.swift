import Foundation

/// Raised when a backend cannot produce a transcript (spec asr-engine:
/// Transcription failure is surfaced). Maps to runtime exit (design D10).
public struct TranscriptionError: Error, LocalizedError {
    public let backend: String
    public let message: String
    public let underlying: (any Error)?

    public init(backend: String, message: String, underlying: (any Error)? = nil) {
        self.backend = backend
        self.message = message
        self.underlying = underlying
    }

    public var errorDescription: String? {
        "\(backend) failed to transcribe: \(message)"
    }
}

/// Backend-agnostic raw output an engine hands back before normalization.
public struct RawTranscription: Sendable {
    public struct RawSegment: Sendable {
        public let start: Double
        public let end: Double
        public let text: String
        public let confidence: Double?

        public init(start: Double, end: Double, text: String, confidence: Double? = nil) {
            self.start = start
            self.end = end
            self.text = text
            self.confidence = confidence
        }
    }

    public let segments: [RawSegment]
    public let language: String?
    public let duration: Double?

    public init(segments: [RawSegment], language: String?, duration: Double?) {
        self.segments = segments
        self.language = language
        self.duration = duration
    }
}

/// Common interface every ASR backend implements (spec asr-engine: Common
/// engine interface). `transcribe` is a template method: the backend-specific
/// work lives in `transcribeRaw`, and normalization plus typed-error wrapping
/// are shared here so every backend behaves identically at the seam.
public protocol Engine: Sendable {
    var id: BackendID { get }

    /// Whether this backend's runtime is usable on the host. Probes lazily and
    /// never throws — absence is reported as false (spec: Availability
    /// detection is graceful).
    func isAvailable() async -> Bool

    /// Backend-specific transcription returning raw segments.
    func transcribeRaw(audioPath: String, options: TranscribeOptions) async throws -> RawTranscription
}

extension Engine {
    /// Static unified-memory estimate for cold-start feasibility (spec
    /// asr-engine: Estimate model requirements).
    public func estimateRequirements(model: String) throws -> ModelRequirements {
        try ModelRegistry.requirements(for: model)
    }

    /// Normalized transcription (spec asr-engine: Transcription returns a
    /// normalized Transcript): segments ordered by start, 1-based ids, full
    /// text concatenated, duration defaulting to the last segment's end.
    public func transcribe(audioPath: String, options: TranscribeOptions) async throws -> Transcript {
        // Engines only ever see 16 kHz mono input (#36): WhisperKit's own
        // resample path corrupts long compressed files (87-minute mp3 →
        // garbage transcript with exit 0), so normalization happens once at
        // this shared seam for every backend. Unreadable input passes
        // through — the engine keeps its established error surface.
        let normalized: AudioNormalizer.NormalizedAudio
        do {
            normalized = try AudioNormalizer.normalize(audioPath: audioPath)
        } catch {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "\(audioPath): \(error.localizedDescription)",
                underlying: error
            )
        }
        defer { normalized.cleanup() }

        let raw: RawTranscription
        do {
            raw = try await transcribeRaw(audioPath: normalized.path, options: options)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "\(audioPath): \(error.localizedDescription)",
                underlying: error
            )
        }

        let ordered = raw.segments.sorted { $0.start < $1.start }
        let segments = ordered.enumerated().map { index, seg in
            TranscriptSegment(
                id: index + 1,
                start: seg.start,
                end: seg.end,
                text: seg.text,
                confidence: seg.confidence
            )
        }
        let text = segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = raw.duration ?? segments.last?.end
        return Transcript(
            text: text,
            language: raw.language ?? options.language,
            duration: duration,
            backend: id.rawValue,
            model: options.model,
            segments: segments
        )
    }
}
