import CryptoKit
import Foundation

/// Row types for the BCNF benchmark store (#14; spec benchmark-store, design
/// D3). Four tables, each JSONL on disk; every non-key attribute depends only
/// on its table's key. Time-of-measurement facts (OS/app version) live on
/// measurement rows, never on the machine row.

/// Stable machine facts. Key: `machine_id` = sha256(chip|memoryGB) prefix.
public struct MachineRow: Codable, Sendable, Equatable {
    public let machineId: String
    public let chip: String
    public let unifiedMemoryGB: Double

    enum CodingKeys: String, CodingKey {
        case machineId = "machine_id"
        case chip
        case unifiedMemoryGB = "unified_memory_gb"
    }

    public init(chip: String, unifiedMemoryGB: Double) {
        self.chip = chip
        self.unifiedMemoryGB = unifiedMemoryGB
        self.machineId = Self.id(chip: chip, unifiedMemoryGB: unifiedMemoryGB)
    }

    public static func id(chip: String, unifiedMemoryGB: Double) -> String {
        shortHash("\(chip)|\(unifiedMemoryGB)")
    }
}

/// The model grid row (catalog). Key: `model_id` = backend|family|size|quant.
public struct ModelRow: Codable, Sendable, Equatable {
    public let modelId: String
    public let backend: String
    public let family: String
    public let size: String
    public let quantization: String
    /// HuggingFace repo id; nil when no verified repo is known.
    public let hfRepo: String?
    /// Pinned repo revision (commit sha) — verification freezes the exact
    /// artifact the row was validated against (#15); bumping the pin implies
    /// re-verifying. nil only when the row is unverified.
    public let hfRevision: String?
    /// Languages the family advertises ("multi" for 99+/1000+ class models).
    public let languages: [String]
    public let estMemoryGB: Double
    /// 1 = first-run set, 2 = representative, 3 = deferred/large.
    public let priority: Int
    /// False until the hf repo id has been checked against the hub — guidance
    /// must never print a guessed URL for unverified rows (#5 lesson).
    public let verified: Bool

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case backend, family, size, quantization
        case hfRepo = "hf_repo"
        case hfRevision = "hf_revision"
        case languages
        case estMemoryGB = "est_memory_gb"
        case priority, verified
    }

    public init(
        backend: String, family: String, size: String, quantization: String,
        hfRepo: String? = nil, hfRevision: String? = nil,
        languages: [String] = ["multi"],
        estMemoryGB: Double, priority: Int, verified: Bool = false
    ) {
        self.backend = backend
        self.family = family
        self.size = size
        self.quantization = quantization
        self.modelId = Self.id(
            backend: backend, family: family, size: size, quantization: quantization)
        self.hfRepo = hfRepo
        self.hfRevision = hfRevision
        self.languages = languages
        self.estMemoryGB = estMemoryGB
        self.priority = priority
        self.verified = verified
    }

    public static func id(
        backend: String, family: String, size: String, quantization: String
    ) -> String {
        "\(backend)|\(family)|\(size)|\(quantization)"
    }
}

/// A registered ground-truth corpus. Key: `corpus_id` = sha256(audio) prefix.
/// Hashes are identity; paths are mutable machine-local facts.
public struct CorpusRow: Codable, Sendable, Equatable {
    public let corpusId: String
    public let name: String
    public let language: String
    public let audioSHA256: String
    public let referenceSHA256: String
    public let duration: Double
    public let audioPath: String
    public let referencePath: String

    enum CodingKeys: String, CodingKey {
        case corpusId = "corpus_id"
        case name, language
        case audioSHA256 = "audio_sha256"
        case referenceSHA256 = "reference_sha256"
        case duration
        case audioPath = "audio_path"
        case referencePath = "reference_path"
    }

    public init(
        name: String, language: String, audioSHA256: String, referenceSHA256: String,
        duration: Double, audioPath: String, referencePath: String
    ) {
        self.name = name
        self.language = language
        self.audioSHA256 = audioSHA256
        self.referenceSHA256 = referenceSHA256
        self.duration = duration
        self.audioPath = audioPath
        self.referencePath = referencePath
        self.corpusId = String(audioSHA256.prefix(12))
    }
}

/// Append-only measurement fact. Key: (model, corpus, machine, measured_at).
public struct MeasurementRow: Codable, Sendable, Equatable {
    public let modelId: String
    public let corpusId: String
    public let machineId: String
    public let measuredAt: Date
    public let metricKind: MetricKind
    public let errorRate: Double
    public let rtf: Double
    public let peakMemoryGB: Double
    public let warmupSeconds: Double
    public let appVersion: String
    public let macosVersion: String
    public let contextErrorRate: Double?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case corpusId = "corpus_id"
        case machineId = "machine_id"
        case measuredAt = "measured_at"
        case metricKind = "metric_kind"
        case errorRate = "error_rate"
        case rtf
        case peakMemoryGB = "peak_memory_gb"
        case warmupSeconds = "warmup_seconds"
        case appVersion = "app_version"
        case macosVersion = "macos_version"
        case contextErrorRate = "context_error_rate"
    }

    public init(
        modelId: String, corpusId: String, machineId: String, measuredAt: Date,
        metricKind: MetricKind, errorRate: Double, rtf: Double, peakMemoryGB: Double,
        warmupSeconds: Double, appVersion: String, macosVersion: String,
        contextErrorRate: Double? = nil
    ) {
        self.modelId = modelId
        self.corpusId = corpusId
        self.machineId = machineId
        self.measuredAt = measuredAt
        self.metricKind = metricKind
        self.errorRate = errorRate
        self.rtf = rtf
        self.peakMemoryGB = peakMemoryGB
        self.warmupSeconds = warmupSeconds
        self.appVersion = appVersion
        self.macosVersion = macosVersion
        self.contextErrorRate = contextErrorRate
    }
}

/// Full SHA-256 hex of a file's bytes — corpus identity (spec corpora).
public func fileSHA256(_ url: URL) throws -> String {
    let digest = SHA256.hash(data: try Data(contentsOf: url))
    return digest.map { String(format: "%02x", $0) }.joined()
}

func shortHash(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined().prefix(12).lowercased()
}
