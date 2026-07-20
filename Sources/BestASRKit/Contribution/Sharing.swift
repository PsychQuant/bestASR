import Foundation

/// Community-benchmark sharing cores (Phase 1 Plan 2 — spec
/// docs/superpowers/specs/2026-07-18-bestasr-community-benchmark-phase1-design.md):
/// the testable logic behind `bench submit`, `corpus pull`, and
/// `corpus contribute`. Network / subprocess mechanics live in the CLI.

/// Default community targets; every CLI command takes overrides.
public enum BenchTargets {
    public static let benchRepo = "PsychQuant/bestASR-bench"
    /// The community org's HF dataset. Manifest hf_*_path values are
    /// namespace-relative, so a future namespace move stays a one-line bump
    /// (and HF keeps a redirect from the old name, so pinned older clients
    /// still resolve).
    public static let hfDataset = "PsychQuant/bestasr-corpus"
}

/// One measurement row as published to the bench repo — MeasurementRow's
/// snake_case fields plus the denormalized machine facts + contributor that
/// make the repo file self-contained (SUBMISSION_FORMAT.md).
public struct SubmissionRow: Codable, Sendable, Equatable {
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
    public let hfRevision: String?
    public let contributor: String
    public let chip: String
    public let unifiedMemoryGB: Double

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
        case contributor, chip
        case unifiedMemoryGB = "unified_memory_gb"
    }

    /// Identity for cross-repo dedupe (mirrors the measurement fact key).
    public var dedupeKey: String {
        "\(modelId)|\(corpusId)|\(machineId)|\(Self.iso8601.string(from: measuredAt))"
    }

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// Packages local measurements for a bench-repo PR: denormalizes machine
/// facts, stamps the contributor, and drops rows the repo already has.
public enum SubmissionPackager {
    /// Only measurements against the CANONICAL corpus travel — rows measured
    /// on local/private corpora are not comparable head-to-head (their
    /// corpus_id fails the bench repo's CI by design) and stay local.
    public static func package(
        local: [MeasurementRow], machines: [MachineRow],
        canonicalCorpusIds: Set<String>,
        publishedKeys: Set<String>, contributor: String
    ) -> [SubmissionRow] {
        let machineById = Dictionary(uniqueKeysWithValues: machines.map { ($0.machineId, $0) })
        return local.compactMap { row in
            guard canonicalCorpusIds.contains(row.corpusId) else { return nil }
            guard let machine = machineById[row.machineId] else { return nil }
            let submission = SubmissionRow(
                modelId: row.modelId, corpusId: row.corpusId, machineId: row.machineId,
                measuredAt: row.measuredAt, metricKind: row.metricKind,
                errorRate: row.errorRate, rtf: row.rtf, peakMemoryGB: row.peakMemoryGB,
                warmupSeconds: row.warmupSeconds, appVersion: row.appVersion,
                macosVersion: row.macosVersion, contextErrorRate: row.contextErrorRate,
                hfRevision: row.hfRevision, contributor: contributor,
                chip: machine.chip, unifiedMemoryGB: machine.unifiedMemoryGB)
            return publishedKeys.contains(submission.dedupeKey) ? nil : submission
        }
    }

    /// `measurements/<UTC basic timestamp>-<contributor>-<machine12>.jsonl`
    public static func filename(date: Date, contributor: String, machineId: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let machine = String(machineId.prefix(12))
        return "\(formatter.string(from: date))-\(contributor)-\(machine).jsonl"
    }

    /// ISO-8601 dates (SUBMISSION_FORMAT.md), one JSON object per line.
    public static func encodeJSONL(_ rows: [SubmissionRow]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try rows.map { row in
            String(decoding: try encoder.encode(row), as: UTF8.self)
        }.joined(separator: "\n") + (rows.isEmpty ? "" : "\n")
    }

    /// Parses published bench-repo jsonl into dedupe keys (bad lines skipped —
    /// the repo's CI owns their validation; pull-side we only need identity).
    public static func publishedKeys(fromJSONL text: String) -> Set<String> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var keys = Set<String>()
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                let row = try? decoder.decode(SubmissionRow.self, from: Data(trimmed.utf8))
            else { continue }
            keys.insert(row.dedupeKey)
        }
        return keys
    }
}

/// Plans a `corpus pull`: which URLs to fetch, where they land, and which
/// SHA each download must match. Downloading itself is the CLI's job.
public enum CorpusPuller {
    public struct PullItem: Sendable, Equatable {
        public let row: CorpusManifestRow
        public let audioURL: URL
        public let referenceURL: URL
        public let audioDestination: URL
        public let referenceDestination: URL
    }

    public static func plan(
        manifest: [CorpusManifestRow], hfDataset: String, destinationRoot: URL
    ) -> [PullItem] {
        manifest.map { row in
            let base = URL(string: "https://huggingface.co/datasets/\(hfDataset)/resolve/main/")!
            return PullItem(
                row: row,
                audioURL: base.appendingPathComponent(row.hfAudioPath),
                referenceURL: base.appendingPathComponent(row.hfReferencePath),
                audioDestination: destinationRoot.appendingPathComponent(row.hfAudioPath),
                referenceDestination: destinationRoot.appendingPathComponent(row.hfReferencePath))
        }
    }

    /// Post-download integrity: both files must hash to the manifest values.
    public static func verify(item: PullItem) throws {
        let audioSHA = try fileSHA256(item.audioDestination)
        guard audioSHA == item.row.audioSHA256 else {
            throw BestASRError.runtime(
                "corpus '\(item.row.corpusId)': audio SHA mismatch "
                    + "(expected \(item.row.audioSHA256.prefix(12))…, got \(audioSHA.prefix(12))…)")
        }
        let referenceSHA = try fileSHA256(item.referenceDestination)
        guard referenceSHA == item.row.referenceSHA256 else {
            throw BestASRError.runtime(
                "corpus '\(item.row.corpusId)': reference SHA mismatch "
                    + "(expected \(item.row.referenceSHA256.prefix(12))…, got \(referenceSHA.prefix(12))…)")
        }
    }
}

/// The `corpus contribute` licensing gate — the machine-enforced half of the
/// privacy discipline (the conversational consent walkthrough lives in the
/// bench-contribute skill).
public enum ContributionGate {
    public static func validate(
        license rawLicense: String, attribution: String, consentAsserted: Bool
    ) throws -> CorpusLicense {
        guard let license = CorpusLicense.parse(rawLicense) else {
            throw BestASRError.usage(
                "license '\(rawLicense)' is not shareable; allowed: "
                    + CorpusLicense.allowed.sorted().joined(separator: ", "))
        }
        guard !attribution.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw BestASRError.usage("attribution is required for a shared corpus entry")
        }
        guard consentAsserted else {
            throw BestASRError.usage(
                "corpus contribution requires --consent: you assert the right to publish "
                    + "this audio AND that identifiable speakers agreed to public release")
        }
        return license
    }
}
