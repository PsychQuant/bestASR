import Foundation

extension BenchmarkStore.Snapshot {
    /// Projects the latest measurements into the BenchmarkRecord shape that
    /// Router/Ranking/Report already consume (design D7) — model identity is
    /// parsed from model_id so legacy-migrated rows project without a grid
    /// join; machine/corpus joins supply chip, language, and duration.
    public func projectedRecords() -> [BenchmarkRecord] {
        let machinesById = Dictionary(uniqueKeysWithValues: machines.map { ($0.machineId, $0) })
        let corporaById = Dictionary(uniqueKeysWithValues: corpora.map { ($0.corpusId, $0) })
        let projected = BenchmarkStore.latestMeasurements(measurements).compactMap { row -> BenchmarkRecord? in
            var parts = row.modelId.split(separator: "|").map(String.init)
            guard parts.count == 4, let corpus = corporaById[row.corpusId] else { return nil }
            // Legacy-migrated ids carry family == size (the flat cache had no
            // family); normalize to the whisper family so re-benchmarks of the
            // same candidate supersede legacy rows (verify #14 M-9).
            if parts[0] != ModelGrid.backendMLXAudio, parts[1] == parts[2] {
                parts[1] = "whisper"
            }
            let backend = parts[0]
            // mlx-audio rows are addressed family/size; whisper backends by size.
            let model = backend == ModelGrid.backendMLXAudio
                ? "\(parts[1])/\(parts[2])" : parts[2]
            return BenchmarkRecord(
                backend: backend, model: model, quantization: parts[3],
                language: corpus.language, metricKind: row.metricKind,
                errorRate: row.errorRate, rtf: row.rtf,
                peakMemoryGB: row.peakMemoryGB, audioDuration: corpus.duration,
                measuredAt: row.measuredAt,
                chip: machinesById[row.machineId]?.chip ?? "",
                macosVersion: row.macosVersion, appVersion: row.appVersion)
        }
        // One record per candidate per language (the old cache's key): latest
        // measurement wins across corpora and eras, so a candidate never
        // occupies multiple ranks and min-max normalization stays honest
        // (verify #14 M-5). Deterministic order for stable tie-breaks (L-19).
        var byCandidate: [String: BenchmarkRecord] = [:]
        for record in projected {
            let key = "\(record.backend)|\(record.model)|\(record.quantization)|\(record.language)|\(record.chip)"
            if let existing = byCandidate[key], existing.measuredAt >= record.measuredAt { continue }
            byCandidate[key] = record
        }
        return byCandidate.sorted { $0.key < $1.key }.map(\.value)
    }
}
