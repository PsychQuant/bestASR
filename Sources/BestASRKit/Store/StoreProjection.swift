import Foundation

extension BenchmarkStore.Snapshot {
    /// Projects the latest measurements into the BenchmarkRecord shape that
    /// Router/Ranking/Report already consume (design D7) — model identity is
    /// parsed from model_id so legacy-migrated rows project without a grid
    /// join; machine/corpus joins supply chip, language, and duration.
    public func projectedRecords() -> [BenchmarkRecord] {
        let machinesById = Dictionary(uniqueKeysWithValues: machines.map { ($0.machineId, $0) })
        let corporaById = Dictionary(uniqueKeysWithValues: corpora.map { ($0.corpusId, $0) })
        return BenchmarkStore.latestMeasurements(measurements).compactMap { row in
            let parts = row.modelId.split(separator: "|").map(String.init)
            guard parts.count == 4, let corpus = corporaById[row.corpusId] else { return nil }
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
    }
}
