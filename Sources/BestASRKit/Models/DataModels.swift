import Foundation

public enum BestASRVersion {
    public static let current = "0.16.0"
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
    // #121: the OS-native backend (Speech.framework's SpeechAnalyzer /
    // SpeechTranscriber, macOS 26+). No download, no dependency — the model
    // ships with the operating system. Appended at the tail for the same
    // reason as #35: store enumeration order stays stable (design D2).
    case appleSpeech = "apple-speech"
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
    /// WhisperKit decode-param knobs (#101): nil rides WhisperKit's own
    /// defaults. Other backends never read these — the knobs suppress
    /// hallucinations at decode time and only WhisperKit's decoder has them
    /// (complementary to the backend-agnostic post-decode filter, #98/#100).
    public let noSpeechThreshold: Double?
    public let compressionRatioThreshold: Double?
    public let logProbThreshold: Double?

    public init(
        model: String, quantization: String, language: String? = nil, prompt: String? = nil,
        deterministicDecode: Bool = false,
        noSpeechThreshold: Double? = nil, compressionRatioThreshold: Double? = nil,
        logProbThreshold: Double? = nil
    ) {
        self.model = model
        self.quantization = quantization
        self.language = language
        self.prompt = prompt
        self.deterministicDecode = deterministicDecode
        self.noSpeechThreshold = noSpeechThreshold
        self.compressionRatioThreshold = compressionRatioThreshold
        self.logProbThreshold = logProbThreshold
    }
}

public struct TranscriptSegment: Sendable, Equatable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let text: String
    public let confidence: Double?
    /// Whisper per-segment hallucination signals (#100): probability the
    /// segment is silence, and the text's gzip compression ratio (repetition
    /// marker). nil when the backend does not compute them (whisper.cpp /
    /// Parakeet) — a nil signal can never trip the `full` filter's thresholds,
    /// which is exactly the per-backend degradation the spec asks for.
    public let noSpeechProb: Double?
    public let compressionRatio: Double?
    /// Cue-level diarization label (`SPEAKER_1`-based, order of first appearance;
    /// #25). nil when diarization did not run or no turn overlapped this segment
    /// — absent means "unknown", never a fabricated speaker (spec diarization).
    public let speaker: String?

    public init(
        id: Int, start: Double, end: Double, text: String, confidence: Double? = nil,
        noSpeechProb: Double? = nil, compressionRatio: Double? = nil,
        speaker: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.confidence = confidence
        self.noSpeechProb = noSpeechProb
        self.compressionRatio = compressionRatio
        self.speaker = speaker
    }

    /// Same segment with a speaker label attached (assignment happens post-transcription).
    public func withSpeaker(_ speaker: String?) -> TranscriptSegment {
        TranscriptSegment(
            id: id, start: start, end: end, text: text, confidence: confidence,
            noSpeechProb: noSpeechProb, compressionRatio: compressionRatio,
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

/// What a measurement row may HONESTLY say about the decode that produced it
/// (#118). Records what we KNOW, not what the backend is — the pre-#118 `Bool?`
/// overloaded `nil` to mean both "legacy row" and "this backend ignores the
/// flag". A row's field stays `Optional`: an ABSENT field (nil) means the row
/// predates the field entirely and makes no claim at all; `nil` is deliberately
/// NOT one of the cases below.
///
/// Wire values are kebab-case and are a cross-repo contract with the bench
/// validator (bestASR-bench `tools/validate_measurements.py`).
///
/// FORWARD COMPAT: decoding is strict — an unrecognized wire value throws, and
/// both consumers turn that throw into a quiet drop (`BenchmarkStore.load`
/// records a warning nothing reads; `SubmissionPackager.publishedKeys` uses
/// `try?`). So adding a case here is a BREAKING change for any older client
/// still reading the same store, and it fails invisibly rather than loudly.
/// Adding a fourth case therefore needs a migration story, not just an
/// `case` line (#131).
public enum DecodeDeterminism: String, Codable, Sendable {
    /// The backend consumed `--decode-deterministic` and it was ON — i.e. the
    /// deterministic *setting was enforced*: temperature-fallback re-decoding
    /// was disabled for this run. That is what we observed; it is deliberately
    /// NOT a promise that re-running yields byte-identical text, which also
    /// depends on runtime, hardware and model revision (#118: never claim more
    /// than the evidence).
    case deterministicEnforced = "deterministic-enforced"
    /// The backend consumed `--decode-deterministic` and it was OFF: temperature
    /// fallback re-decoding is live, so a re-run may differ.
    case fallbackEnabled = "fallback-enabled"
    /// The backend ignores `--decode-deterministic` entirely (mlx-audio treats it
    /// as a silent no-op; the Fluid backends have no such knob). This makes NO
    /// claim about whether that backend's decode is actually reproducible — we
    /// don't know, and saying either "deterministic" or "fallback" would be a
    /// lie (#118).
    case flagNotConsumed = "flag-not-consumed"

    /// Backends that actually read `--decode-deterministic`. Adding a backend
    /// here is the ONE edit that lets its rows start making a determinism claim
    /// — until then it honestly reports `.flagNotConsumed`.
    public static let flagConsumingBackends: Set<String> = [
        ModelGrid.backendWhisperKit, ModelGrid.backendWhisperCpp,
    ]

    /// The honest gate (#120 item 1): which condition a row measured on
    /// `backend` may claim, given the flag the user asked for. Non-optional —
    /// every real measurement can say *something*; the row's optionality is
    /// reserved for legacy rows that predate the field.
    public static func forBackend(_ backend: String, flagRequested: Bool) -> DecodeDeterminism {
        guard flagConsumingBackends.contains(backend) else { return .flagNotConsumed }
        return flagRequested ? .deterministicEnforced : .fallbackEnabled
    }
}

/// How a measurement was produced (#111) — the `run_kind` value domain as the
/// CLI accepts it (#120 item 2).
///
/// SCOPE, deliberately: this constrains the `--run-kind` OPTION, not the stored
/// field. `MeasurementRow.runKind` / `SubmissionRow.runKind` stay `String?`, so
/// a library caller can still store a value outside this domain, and bench CI
/// stays the backstop for that path. That is the opposite choice from
/// `DecodeDeterminism`, on purpose: that field's domain is *derived* from this
/// repo's own backend roster (a total function over it), whereas run_kind is
/// human-typed provenance whose vocabulary is already demonstrably incomplete —
/// `scripts/regression-gate.sh` benchmarks with no `--run-kind` at all. Closing
/// this domain at the row type would trade a loud CI failure for a silent
/// stale-data read (an undecodable row is dropped, promoting a superseded one).
///
/// KEEP IN SYNC with the bench validator's `run_kind` set (bestASR-bench
/// `tools/validate_measurements.py`). There is no mechanical link: a value added
/// here and not there fails only in the bench repo's CI, and vice versa
/// (#120 Residue, deliberately unfixed).
public enum RunKind: String, Codable, Sendable, CaseIterable {
    /// A sweep driven by `scripts/release-sweep.sh`.
    case releaseSweep = "release-sweep"
    /// A one-off local benchmark.
    case adhoc
}

/// One (backend × model × quantization) configuration to measure.
public struct BenchmarkCandidate: Sendable, Equatable, Hashable {
    public let backend: BackendID
    /// The model itself, not a spelling of it.
    ///
    /// A candidate is always built from a catalog row, so its identity is
    /// known at construction. Storing the identity rather than an address is
    /// what stops the string from being flattened here and re-parsed later:
    /// every round of this change fixed one instance of "a consumer re-derived
    /// something the producer already knew".
    public let identity: ModelID
    public let quantization: String

    /// Derived, never stored — a candidate cannot carry an address that
    /// disagrees with the model it names.
    public var model: String { ModelGrid.address(for: identity) }

    public init(backend: BackendID, identity: ModelID, quantization: String) {
        self.backend = backend
        self.identity = identity
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

    /// Which model this measured, as a value — `nil` when the record predates
    /// #183 or its stored key carried no usable family or size. `model` above
    /// is how the record is ADDRESSED; this is what it IS.
    ///
    /// Optional on purpose: `Decodable` gives Optionals `decodeIfPresent`, so
    /// a `benchmarks.json` written before this change still reads.
    public var identity: ModelID?

    /// Whether the record names its artifact well enough to be compared with
    /// another.
    ///
    /// **Derived, not stored** (round-4 verify, findings C2/C3). It was a
    /// stored `Bool` defaulting to `true`, which failed in two directions at
    /// once: Swift's synthesized `Decodable` does not consult property
    /// defaults, so every pre-#183 record threw `keyNotFound` and was
    /// reported as a corrupt cache; and both paths that rebuild a record —
    /// the per-candidate collapse here and `Router.aggregate` — omitted it,
    /// so any candidate measured on more than one corpus was silently vouched
    /// for again. Computing it from the record's own components removes both:
    /// there is no key to be missing and no argument to forget.
    public var identityComplete: Bool {
        guard let identity else { return false }
        return ModelGrid.namesCompletely(
            identity: identity, quantization: Quantization(serialised: quantization))
    }

    /// Whether the record can say WHICH artifact produced it — set by the
    /// projection from the record's OWN facts, never from today's catalog.
    ///
    /// A DIFFERENT question from `identityComplete`, and round 9's verify
    /// showed what conflating them costs. A record can name its model
    /// completely and still be unable to say which published variant the
    /// runtime chose for it; conversely a record whose stored quantization
    /// segment reads `default` may carry a commit-sha pin that freezes the
    /// artifact exactly. Judged by the catalog, the two groups came out
    /// **backwards**: the 44 sha-pinned measurements were called incomparable
    /// and the 47 whose precision was a dependency default were vouched for.
    ///
    /// `nil` for records that predate the field. A record that cannot say is
    /// not attested, so `nil` and `false` mean the same thing to a caller —
    /// but Optional is what lets legacy JSON decode at all (#183 round-4 C2:
    /// a stored non-Optional `Bool` threw `keyNotFound` on every older record).
    public var artifactAttested: Bool?

    /// `artifactAttested`, with the two ways of not being attested collapsed —
    /// which is correct HERE because a record that does not say and a record
    /// that says no are equally unable to vouch for themselves.
    public var attestsArtifact: Bool { artifactAttested == true }

    public init(
        backend: String, model: String, quantization: String,
        identity: ModelID? = nil, artifactAttested: Bool? = nil, language: String,
        metricKind: MetricKind, errorRate: Double, rtf: Double, peakMemoryGB: Double,
        audioDuration: Double, measuredAt: Date, chip: String, macosVersion: String,
        appVersion: String
    ) {
        self.identity = identity
        self.artifactAttested = artifactAttested
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
    /// How the model is spelled for a user and for the store.
    ///
    /// Derived from `identity` wherever one is known — never assigned
    /// independently of it. The cold-start path used to assign a bare size
    /// here while every later layer treated the field as an address, and the
    /// bare size travelled untouched to the engine (#183, round-8 verify).
    public let model: String
    /// The model itself, when this catalog can name one.
    ///
    /// `nil` only for a `--model` string the catalog cannot place, which
    /// travels as the user typed it because there is nothing else true to say
    /// about it.
    public let identity: ModelID?
    public let quantization: String
    public let profile: RouterProfile
    public let language: String?
    public let dataSource: RecommendationDataSource
    public let measured: MeasuredSummary?
    public let reason: [String]
    public let warnings: [String]

    /// - Parameters:
    ///   - identity: the model, when this catalog can name one.
    ///   - unplaceableName: the string to carry when it cannot — a `--model`
    ///     value no runtime here publishes. Ignored whenever `identity` is
    ///     present, so the spelling can never disagree with the model.
    ///
    /// There is deliberately no way to pass `model` directly. The cold-start
    /// path used to set it to a bare size while `identity` said otherwise, and
    /// nothing could notice: the two were independent fields saying the same
    /// thing (#183, round-8 verify).
    public init(
        backend: BackendID, identity: ModelID?, unplaceableName: String? = nil,
        quantization: String,
        profile: RouterProfile,
        language: String?, dataSource: RecommendationDataSource, measured: MeasuredSummary?,
        reason: [String], warnings: [String]
    ) {
        self.backend = backend
        self.model = identity.map(ModelGrid.address(for:)) ?? unplaceableName ?? ""
        self.identity = identity
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
            backend: backend, identity: identity, unplaceableName: model,
            quantization: quantization,
            profile: profile, language: language, dataSource: dataSource, measured: measured,
            reason: reasons + reason, warnings: warnings)
    }

    /// Copy merging extra reasons and warnings (#105: auto language-detection
    /// notes travel on the recommendation like every other routing fact).
    public func merging(reasons extraReasons: [String], warnings extraWarnings: [String])
        -> ASRRecommendation {
        guard !extraReasons.isEmpty || !extraWarnings.isEmpty else { return self }
        return ASRRecommendation(
            backend: backend, identity: identity, unplaceableName: model,
            quantization: quantization,
            profile: profile, language: language, dataSource: dataSource, measured: measured,
            reason: extraReasons + reason, warnings: warnings + extraWarnings)
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
