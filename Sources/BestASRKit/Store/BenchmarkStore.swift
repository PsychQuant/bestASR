import Foundation

/// The machine-local BCNF benchmark store (#14; spec benchmark-store): four
/// JSONL tables under one directory, append-only measurements, and a
/// latest-per-(model, corpus, machine) projection for routing/reporting.
public struct BenchmarkStore: Sendable {
    public let directory: URL

    static let tables = ["machines", "models", "corpora", "measurements"]

    public init(directory: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bestasr/store", isDirectory: true)
    }

    // MARK: - Load

    public struct Snapshot: Sendable {
        public var machines: [MachineRow]
        public var models: [ModelRow]
        public var corpora: [CorpusRow]
        public var measurements: [MeasurementRow]
        public var warnings: [String]
    }

    /// Loads all four tables. Malformed lines are skipped loudly (table +
    /// line number in the warning), never fatally (spec: Corrupt rows degrade
    /// loudly). Triggers the one-time legacy migration when applicable.
    public func load() throws -> Snapshot {
        try migrateLegacyIfPresent()
        return loadRaw()
    }

    /// Table reads without the migration trigger — used by load() and by the
    /// migration itself (calling load() from migration would recurse: the
    /// legacy file still exists mid-migration).
    func loadRaw() -> Snapshot {
        var warnings: [String] = []
        func rows<T: Decodable>(_ table: String, _ type: T.Type) -> [T] {
            let url = directory.appendingPathComponent("\(table).jsonl")
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var result: [T] = []
            for (index, line) in content.split(separator: "\n", omittingEmptySubsequences: true)
                .enumerated()
            {
                do {
                    result.append(try decoder.decode(T.self, from: Data(line.utf8)))
                } catch {
                    warnings.append("\(table).jsonl line \(index + 1): skipped malformed row")
                }
            }
            return result
        }
        return Snapshot(
            machines: rows("machines", MachineRow.self),
            models: rows("models", ModelRow.self),
            corpora: rows("corpora", CorpusRow.self),
            measurements: rows("measurements", MeasurementRow.self),
            warnings: warnings
        )
    }

    // MARK: - Append / upsert

    public func append(measurement: MeasurementRow) throws {
        try appendLine(table: "measurements", row: measurement)
    }

    /// Machines and corpora upsert by key (stable-fact tables); models are
    /// replaced wholesale by the grid seed (catalog is code-owned).
    public func upsert(machine: MachineRow) throws {
        try migrateLegacyIfPresent()
        guard !loadRaw().machines.contains(where: { $0.machineId == machine.machineId }) else {
            return
        }
        try appendLine(table: "machines", row: machine)
    }

    public func upsert(corpus: CorpusRow) throws {
        try migrateLegacyIfPresent()
        let snapshot = loadRaw()
        var corpora = snapshot.corpora.filter { $0.corpusId != corpus.corpusId }
        corpora.append(corpus)
        try rewrite(table: "corpora", rows: corpora)
    }

    /// Seeds/refreshes the models table from the code-owned grid.
    public func seed(models: [ModelRow]) throws {
        try rewrite(table: "models", rows: models)
    }

    // MARK: - Projection

    /// Latest measurement per (model, corpus, machine) — append-only history
    /// stays in the file; consumers see only the newest row per key triple.
    public static func latestMeasurements(_ measurements: [MeasurementRow]) -> [MeasurementRow] {
        var latest: [String: MeasurementRow] = [:]
        for row in measurements {
            let key = "\(row.modelId)|\(row.corpusId)|\(row.machineId)"
            if let existing = latest[key], existing.measuredAt >= row.measuredAt { continue }
            latest[key] = row
        }
        return Array(latest.values)
    }

    // MARK: - Legacy migration (design D4)

    /// Decomposes a legacy flat `benchmarks.json` into the four tables, then
    /// renames it `.bak`. Idempotent: the `.bak` rename removes the trigger.
    func migrateLegacyIfPresent() throws {
        let legacyURL = directory.deletingLastPathComponent()
            .appendingPathComponent("benchmarks.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: legacyURL),
            let records = try? decoder.decode([BenchmarkRecord].self, from: data)
        else {
            // Loud, not silent: the old cache surfaced corruption as an error
            // (verify #14 L-17) — keep the signal while still unblocking.
            FileHandle.standardError.write(Data(
                "warning: legacy benchmark cache at \(legacyURL.path) is corrupt — renamed to .bak without migration; re-run bestasr benchmark\n".utf8))
            try? FileManager.default.moveItem(
                at: legacyURL, to: legacyURL.appendingPathExtension("bak"))
            return
        }

        var seenMachines = Set(loadRaw().machines.map(\.machineId))
        var seenCorpora = Set(loadRaw().corpora.map(\.corpusId))
        for record in records {
            // Machine facts: legacy records don't carry memory — 0 marks unknown.
            let machine = MachineRow(chip: record.chip, unifiedMemoryGB: 0)
            if seenMachines.insert(machine.machineId).inserted {
                try appendLine(table: "machines", row: machine)
            }
            // Synthetic corpus identity: legacy rows lack the audio hash.
            let corpusKey = "legacy|\(record.language)|\(record.audioDuration)"
            let corpus = CorpusRow(
                name: "legacy-\(record.language)", language: record.language,
                audioSHA256: shortHash(corpusKey) + String(repeating: "0", count: 52),
                referenceSHA256: "", duration: record.audioDuration,
                audioPath: "", referencePath: "")
            if seenCorpora.insert(corpus.corpusId).inserted {
                try appendLine(table: "corpora", row: corpus)
            }
            let modelId = ModelRow.id(
                backend: record.backend, family: record.model, size: record.model,
                quantization: record.quantization)
            let measurement = MeasurementRow(
                modelId: modelId, corpusId: corpus.corpusId, machineId: machine.machineId,
                measuredAt: record.measuredAt, metricKind: record.metricKind,
                errorRate: record.errorRate, rtf: record.rtf,
                peakMemoryGB: record.peakMemoryGB, warmupSeconds: 0,
                appVersion: record.appVersion, macosVersion: record.macosVersion)
            try appendLine(table: "measurements", row: measurement)
        }
        try FileManager.default.moveItem(
            at: legacyURL, to: legacyURL.appendingPathExtension("bak"))
    }

    // MARK: - IO

    private func appendLine<T: Encodable>(table: String, row: T) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line = try encoder.encode(row) + Data("\n".utf8)
        let url = directory.appendingPathComponent("\(table).jsonl")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    private func rewrite<T: Encodable>(table: String, rows: [T]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var payload = Data()
        for row in rows {
            payload += try encoder.encode(row) + Data("\n".utf8)
        }
        try payload.write(to: directory.appendingPathComponent("\(table).jsonl"))
    }
}
