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
///
/// The row holds a structured ``ModelID`` and a ``Quantization`` rather than
/// four loose strings (#183), while the wire format stays exactly as it was:
/// the same flat JSON columns and the same four-segment key. Nothing already
/// written to `models.jsonl` needs rewriting for this change.
public struct ModelRow: Codable, Sendable, Equatable {
    public let modelId: String
    /// The runtime hosting this model. Not part of the identity — the same
    /// model under two runtimes is one model measured two ways.
    public let backend: String
    public let identity: ModelID
    public let quantization: Quantization

    /// The family half of ``identity``. Derived, so the two cannot disagree.
    public var family: String { identity.family }
    /// The version half of ``identity``. Derived, so the two cannot disagree.
    public var size: String { identity.size }

    /// HuggingFace repo id; nil when no verified repo is known.
    public let hfRepo: String?
    /// Pinned repo revision (full commit sha) — verification freezes the
    /// exact artifact the row was validated against (#15); bumping the pin
    /// implies re-verifying. Required for verified HF-backed mlx-audio rows;
    /// nil elsewhere (whisper backends fetch through their own engines).
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
        backend: String, identity: ModelID, quantization: Quantization,
        hfRepo: String? = nil, hfRevision: String? = nil,
        languages: [String] = ["multi"],
        estMemoryGB: Double, priority: Int, verified: Bool = false
    ) {
        self.backend = backend
        self.identity = identity
        self.quantization = quantization
        self.modelId = Self.id(
            backend: backend, identity: identity, quantization: quantization)
        self.hfRepo = hfRepo
        self.hfRevision = hfRevision
        self.languages = languages
        self.estMemoryGB = estMemoryGB
        self.priority = priority
        self.verified = verified
    }

    /// Build a row the way the catalog literals read: family and size spelled
    /// out, quantization stated as one of the four facts it can be. Traps on a
    /// family or size that names nothing, because a catalog row is a
    /// compile-time constant — failing at launch, naming the row, beats
    /// carrying an identity that identifies nothing.
    public init(
        backend: String, family: String, size: String, quantization: Quantization,
        hfRepo: String? = nil, hfRevision: String? = nil,
        languages: [String] = ["multi"],
        estMemoryGB: Double, priority: Int, verified: Bool = false
    ) {
        guard let identity = ModelID(family: family, size: size) else {
            preconditionFailure(
                "catalog row names no model: family \"\(family)\", size \"\(size)\"")
        }
        self.init(
            backend: backend, identity: identity, quantization: quantization,
            hfRepo: hfRepo, hfRevision: hfRevision, languages: languages,
            estMemoryGB: estMemoryGB, priority: priority, verified: verified)
    }

    /// The store key for a structured identity — how every row now gets its own.
    public static func id(
        backend: String, identity: ModelID, quantization: Quantization
    ) -> String {
        id(backend: backend, family: identity.family, size: identity.size,
           quantization: quantization.serialised)
    }

    /// The store key from loose segments. Kept because reading history means
    /// joining four strings that a `ModelID` may decline to carry — the
    /// projection path parses records written before this change.
    public static func id(
        backend: String, family: String, size: String, quantization: String
    ) -> String {
        "\(backend)|\(family)|\(size)|\(quantization)"
    }

    // The row's JSON keeps the flat columns the store has always written —
    // holding a `ModelID` is an in-memory shape, not a file-format change.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let family = try container.decode(String.self, forKey: .family)
        let size = try container.decode(String.self, forKey: .size)
        guard let identity = ModelID(family: family, size: size) else {
            throw DecodingError.dataCorruptedError(
                forKey: .family, in: container,
                debugDescription:
                    "a record must name a family and a size; got \"\(family)\" and \"\(size)\"")
        }
        self.identity = identity
        self.backend = try container.decode(String.self, forKey: .backend)
        self.quantization = Quantization(
            serialised: try container.decode(String.self, forKey: .quantization))
        self.hfRepo = try container.decodeIfPresent(String.self, forKey: .hfRepo)
        self.hfRevision = try container.decodeIfPresent(String.self, forKey: .hfRevision)
        self.languages = try container.decode([String].self, forKey: .languages)
        self.estMemoryGB = try container.decode(Double.self, forKey: .estMemoryGB)
        self.priority = try container.decode(Int.self, forKey: .priority)
        self.verified = try container.decode(Bool.self, forKey: .verified)

        // The key is derived, never trusted: a stored key that disagrees with
        // the columns beside it means one of the two is lying, and a silent
        // choice between them would decide which measurements get compared.
        let derived = Self.id(
            backend: backend, family: family, size: size,
            quantization: quantization.serialised)
        let stored = try container.decode(String.self, forKey: .modelId)
        guard stored == derived else {
            throw DecodingError.dataCorruptedError(
                forKey: .modelId, in: container,
                debugDescription: "model_id \"\(stored)\" disagrees with its columns (\(derived))")
        }
        self.modelId = derived
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(backend, forKey: .backend)
        try container.encode(identity.family, forKey: .family)
        try container.encode(identity.size, forKey: .size)
        try container.encode(quantization.serialised, forKey: .quantization)
        try container.encodeIfPresent(hfRepo, forKey: .hfRepo)
        try container.encodeIfPresent(hfRevision, forKey: .hfRevision)
        try container.encode(languages, forKey: .languages)
        try container.encode(estMemoryGB, forKey: .estMemoryGB)
        try container.encode(priority, forKey: .priority)
        try container.encode(verified, forKey: .verified)
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
    public let referenceProvenance: String?
    public let license: String?
    public let attribution: String?
    public let contributor: String?

    enum CodingKeys: String, CodingKey {
        case corpusId = "corpus_id"
        case name, language
        case audioSHA256 = "audio_sha256"
        case referenceSHA256 = "reference_sha256"
        case duration
        case audioPath = "audio_path"
        case referencePath = "reference_path"
        case referenceProvenance = "reference_provenance"
        case license, attribution, contributor
    }

    public init(
        name: String, language: String, audioSHA256: String, referenceSHA256: String,
        duration: Double, audioPath: String, referencePath: String,
        referenceProvenance: String? = nil, license: String? = nil,
        attribution: String? = nil, contributor: String? = nil
    ) {
        self.name = name
        self.language = language
        self.audioSHA256 = audioSHA256
        self.referenceSHA256 = referenceSHA256
        self.duration = duration
        self.audioPath = audioPath
        self.referencePath = referencePath
        self.referenceProvenance = referenceProvenance
        self.license = license
        self.attribution = attribution
        self.contributor = contributor
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
    /// Hugging Face revision pin of the model AS SEEDED at measure time (#16 —
    /// the catalog table is rewritten wholesale on every seed, so the pin a
    /// number was measured against must live on the measurement itself).
    /// nil for legacy rows and models without an HF pin.
    public let hfRevision: String?
    /// How this measurement was produced: "release-sweep" (scripts/release-sweep.sh)
    /// vs "adhoc" (a one-off local benchmark). nil for legacy rows (#111).
    public let runKind: String?
    /// What is known about this row's decode: enforced determinism, live
    /// temperature fallback, or a backend that ignores the flag (#118 — see
    /// `DecodeDeterminism`). nil ONLY for legacy rows measured before the field
    /// existed; "this backend ignores the flag" is `.flagNotConsumed`, not nil.
    public let decodeDeterministic: DecodeDeterminism?

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
        case hfRevision = "hf_revision"
        case runKind = "run_kind"
        case decodeDeterministic = "decode_deterministic"
    }

    public init(
        modelId: String, corpusId: String, machineId: String, measuredAt: Date,
        metricKind: MetricKind, errorRate: Double, rtf: Double, peakMemoryGB: Double,
        warmupSeconds: Double, appVersion: String, macosVersion: String,
        contextErrorRate: Double? = nil, hfRevision: String? = nil,
        runKind: String? = nil, decodeDeterministic: DecodeDeterminism? = nil
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
        self.hfRevision = hfRevision
        self.runKind = runKind
        self.decodeDeterministic = decodeDeterministic
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
