import Foundation

/// Machine-local benchmark result cache (design D6; spec benchmark: Persist
/// benchmark results to a machine-local cache).
///
/// A plain JSON array of `BenchmarkRecord` at `~/.bestasr/benchmarks.json` —
/// human-readable, diffable, and consumed by the router. Records are keyed by
/// (backend, model, quantization, language); a new measurement replaces the
/// prior record for its key.
@available(*, deprecated, message: "superseded by BenchmarkStore (#14); retained for the legacy file format and report key helper")
public struct BenchmarkCache: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func live() -> BenchmarkCache {
        BenchmarkCache(
            fileURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".bestasr/benchmarks.json")
        )
    }

    static func key(_ record: BenchmarkRecord) -> String {
        [record.backend, record.model, record.quantization, record.language]
            .joined(separator: "|")
    }

    /// Missing cache file means "never benchmarked" — an empty list, not an error.
    public func load() throws -> [BenchmarkRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([BenchmarkRecord].self, from: data)
        } catch {
            throw BestASRError.runtime(
                "benchmark cache at \(fileURL.path) is corrupt (\(error.localizedDescription)); "
                    + "delete it and re-run bestasr benchmark"
            )
        }
    }

    /// Insert or replace records by key, then persist atomically.
    @discardableResult
    public func upsert(_ records: [BenchmarkRecord]) throws -> [BenchmarkRecord] {
        var byKey = [String: BenchmarkRecord]()
        for existing in try load() {
            byKey[Self.key(existing)] = existing
        }
        for record in records {
            byKey[Self.key(record)] = record
        }
        let merged = byKey.values.sorted {
            Self.key($0) < Self.key($1)
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(merged).write(to: fileURL, options: .atomic)
        return merged
    }
}
