import Foundation

public enum BestASRVersion {
    public static let current = "0.11.0"
}

// MARK: - Backends

public enum BackendID: String, Codable, CaseIterable, Sendable {
    case whisperKit = "whisperkit"
    case whisperCpp = "whisper.cpp"
    // #35: first non-Whisper family (FluidAudio Parakeet, zero new deps).
    // Appended at the tail — store enumeration order stays stable (design D2).
    // "fluid-parakeet" (vendor-prefixed) stays distinguishable from the
    // mlx-audio parakeet REFERENCE row that shares the family name (#20).
    case fluidParakeet = "fluid-parakeet"
    case fluidParaformer = "fluid-paraformer"
    case fluidSenseVoice = "fluid-sensevoice"
    case mlxAudio = "mlx-audio"
}

// MARK: - Detection

/// Facts about the host machine relevant to ASR routing (Apple Silicon only).
public struct SystemInfo: Sendable, Equatable {
    public let chip: String
    public let unifiedMemoryGB: Double
    /// `true`/`false` when the chip generation is known; `nil` when unknown
    /// (detection degrades to unknown rather than failing — spec system-detection).
    public let hasANE: Bool?
    public let macosVersion: String

    public init(chip: String, unifiedMemoryGB: Double, hasANE: Bool?, macosVersion: String) {
        self.chip = chip
        self.unifiedMemoryGB = unifiedMemoryGB
        self.hasANE = hasANE
        self.macosVersion = macosVersion
    }
}

/// Properties of an input audio file.
public struct AudioInfo: Sendable, Equatable {
    public let path: String
    public let duration: Double?
    public let format: String?
    public let sampleRate: Int?
    public let channels: Int?
    public let language: String?

    public init(
        path: String,
        duration: Double? = nil,
        format: String? = nil,
        sampleRate: Int? = nil,
        channels: Int? = nil,
        language: String? = nil
    ) {
        self.path = path
        self.duration = duration
        self.format = format
        self.sampleRate = sampleRate
        self.channels = channels
        self.language = language
    }
}

// MARK: - Transcription

/// Resolved parameters handed to an engine's `transcribe`.
public struct TranscribeOptions: Sendable, Equatable {
    public let model: String
    public let quantization: String
    public let language: String?
    /// Rendered context vocabulary (spec asr-engine: forwarded to the
    /// backend's prompt mechanism; nil adds nothing to the invocation).
    public let prompt: String?
    /// Disable temperature-fallback re-decoding so the same audio always
    /// yields the same text (#34 regression gate). Whisper decoders retry
    /// low-quality segments at temperature > 0 — stochastic sampling that was
    /// observed live to flip a corpus CER between runs. The gate's canary
    /// needs reproducibility more than the occasional rescue; normal
    /// transcription keeps the fallback.
    public let deterministicDecode: Bool

    public init(
        model: String, quantization: String, language: String? = nil, prompt: String? = nil,
        deterministicDecode: Bool = false
    ) {
        self.model = model
        self.quantization = quantization
        self.language = language
        self.prompt = prompt
        self.deterministicDecode = deterministicDecode
    }
}

public struct TranscriptSegment: Sendable, Equatable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let text: String
    public let confidence: Double?
    /// Cue-level diarization label (`SPEAKER_1`-based, order of first appearance;
    /// #25). nil when diarization did not run or no turn overlapped this segment
    /// — absent means "unknown", never a fabricated speaker (spec diarization).
    public let speaker: String?

    public init(
        id: Int, start: Double, end: Double, text: String, confidence: Double? = nil,
        speaker: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.confidence = confidence
        self.speaker = speaker
    }

    /// Same segment with a speaker label attached (assignment happens post-transcription).
    public func withSpeaker(_ speaker: String?) -> TranscriptSegment {
        TranscriptSegment(
            id: id, start: start, end: end, text: text, confidence: confidence,
            speaker: speaker)
    }
}

/// A normalized transcription result, independent of the backend used.
public struct Transcript: Sendable, Equatable {
    public let text: String
    public let language: String?
    public let duration: Double?
    public let backend: String
    public let model: String
    public let segments: [TranscriptSegment]

    public init(
        text: String,
        language: String?,
        duration: Double?,
        backend: String,
        model: String,
        segments: [TranscriptSegment] = []
    ) {
        self.text = text
        self.language = language
        self.duration = duration
        self.backend = backend
        self.model = model
        self.segments = segments
    }
}

// MARK: - Requirements

/// Estimated unified-memory footprint of a model (static table, cold-start use).
public struct ModelRequirements: Sendable, Equatable {
    public let model: String
    public let memoryGB: Double

    public init(model: String, memoryGB: Double) {
        self.model = model
        self.memoryGB = memoryGB
    }
}

// MARK: - Benchmark

public enum MetricKind: String, Codable, Sendable {
    case cer
    case wer
}

/// One (backend × model × quantization) configuration to measure.
public struct BenchmarkCandidate: Sendable, Equatable, Hashable {
    public let backend: BackendID
    public let model: String
    public let quantization: String

    public init(backend: BackendID, model: String, quantization: String) {
        self.backend = backend
        self.model = model
        self.quantization = quantization
    }
}

/// A persisted measurement for one candidate on this machine.
public struct BenchmarkRecord: Codable, Sendable, Equatable {
    public let backend: String
    public let model: String
    public let quantization: String
    public let language: String
    public let metricKind: MetricKind
    /// 0...1+, lower is better (CER can exceed 1 on catastrophic output).
    public let errorRate: Double
    /// Wall-clock transcription seconds ÷ audio seconds (lower is faster).
    public let rtf: Double
    public let peakMemoryGB: Double
    public let audioDuration: Double
    public let measuredAt: Date
    public let chip: String
    public let macosVersion: String
    public let appVersion: String

    public init(
        backend: String, model: String, quantization: String, language: String,
        metricKind: MetricKind, errorRate: Double, rtf: Double, peakMemoryGB: Double,
        audioDuration: Double, measuredAt: Date, chip: String, macosVersion: String,
        appVersion: String
    ) {
        self.backend = backend
        self.model = model
        self.quantization = quantization
        self.language = language
        self.metricKind = metricKind
        self.errorRate = errorRate
        self.rtf = rtf
        self.peakMemoryGB = peakMemoryGB
        self.audioDuration = audioDuration
        self.measuredAt = measuredAt
        self.chip = chip
        self.macosVersion = macosVersion
        self.appVersion = appVersion
    }

    /// Times-realtime (higher is faster); guards divide-by-zero on degenerate RTF.
    public var timesRealtime: Double { rtf > 0 ? 1.0 / rtf : 0 }
}

// MARK: - Recommendation

public enum RecommendationDataSource: String, Codable, Sendable {
    case measured
    case coldStartPrior = "cold_start_prior"
}

/// Measured figures cited by a recommendation whose data source is `measured`.
public struct MeasuredSummary: Codable, Sendable, Equatable {
    public let metricKind: MetricKind
    public let errorRate: Double
    public let rtf: Double

    public init(metricKind: MetricKind, errorRate: Double, rtf: Double) {
        self.metricKind = metricKind
        self.errorRate = errorRate
        self.rtf = rtf
    }
}

/// A chosen backend/model/quantization plus the reasoning behind it.
public struct ASRRecommendation: Sendable, Equatable {
    public let backend: BackendID
    public let model: String
    public let quantization: String
    public let profile: RouterProfile
    public let language: String?
    public let dataSource: RecommendationDataSource
    public let measured: MeasuredSummary?
    public let reason: [String]
    public let warnings: [String]

    public init(
        backend: BackendID, model: String, quantization: String, profile: RouterProfile,
        language: String?, dataSource: RecommendationDataSource, measured: MeasuredSummary?,
        reason: [String], warnings: [String]
    ) {
        self.backend = backend
        self.model = model
        self.quantization = quantization
        self.profile = profile
        self.language = language
        self.dataSource = dataSource
        self.measured = measured
        self.reason = reason
        self.warnings = warnings
    }

    /// Copy prepending extra reasons (e.g. the `auto` profile-resolution note),
    /// so callers do not rebuild the struct field-by-field (#29 verify #12).
    public func prepending(reasons: [String]) -> ASRRecommendation {
        guard !reasons.isEmpty else { return self }
        return ASRRecommendation(
            backend: backend, model: model, quantization: quantization, profile: profile,
            language: language, dataSource: dataSource, measured: measured,
            reason: reasons + reason, warnings: warnings)
    }
}

// MARK: - Router profiles

public enum RouterProfile: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case xhigh
    case max

    /// Weights over the two measured axes. low/medium/high carry the old
    /// fast/balanced/accurate anchors (renormalized from the design-brief
    /// four-axis table — memory_fit and stability do not apply to candidates
    /// that already ran on this machine); xhigh is the midpoint step toward
    /// max, and max = 1.0 is a pure accuracy argmax ("best regardless of
    /// time", #29) whose equal-accuracy ties break to the faster candidate.
    public var accuracyWeight: Double {
        switch self {
        case .low: 0.267
        case .medium: 0.5
        case .high: 0.8
        case .xhigh: 0.9
        case .max: 1.0
        }
    }

    public var speedWeight: Double { 1.0 - accuracyWeight }
}

// MARK: - CLI selection request

/// Parsed selection flags shared by `recommend` and `transcribe`.
public struct SelectionRequest: Sendable {
    public let profileName: String
    public let backendOverride: String?
    public let modelOverride: String?
    public let requestedLanguage: String?
    /// Explicit --context-dir; nil resolves per the three-layer precedence.
    public let contextDir: String?

    public init(
        profileName: String,
        backendOverride: String?,
        modelOverride: String?,
        requestedLanguage: String?,
        contextDir: String? = nil
    ) {
        self.profileName = profileName
        self.backendOverride = backendOverride
        self.modelOverride = modelOverride
        self.requestedLanguage = requestedLanguage
        self.contextDir = contextDir
    }
}

// MARK: - Output formats

public enum OutputFormat: String, CaseIterable, Sendable {
    case txt, json, srt, vtt

    public static var allNames: [String] { allCases.map(\.rawValue) }
}

// MARK: - Errors

/// Typed failures with the exit-code mapping from design D10.
public enum BestASRError: Error, LocalizedError, Equatable {
    /// Exit 2 — caller mistake (missing file, bad reference, unknown name).
    case usage(String)
    /// Exit 1 — runtime failure (no backend, transcription failed, all candidates failed).
    case runtime(String)

    public var errorDescription: String? {
        switch self {
        case .usage(let message), .runtime(let message): message
        }
    }

    public var exitCode: Int32 {
        switch self {
        case .usage: 2
        case .runtime: 1
        }
    }
}
