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
            let parts = row.modelId.split(separator: "|").map(String.init)
            guard parts.count == 4, let corpus = corporaById[row.corpusId] else { return nil }
            let backend = parts[0]
            // Canonicalise on READ (#183). The stored key is never rewritten;
            // this says what it means in today's catalog, so a measurement
            // taken before the catalog stated its quantization collapses with
            // one taken after into a single candidate instead of competing
            // with itself in the ranking pool.
            let canon = ModelGrid.canonical(
                backend: backend, family: parts[1], size: parts[2], quantization: parts[3])
            let identity = canon?.identity
            let quantization = canon?.quantization ?? Quantization(serialised: parts[3])
            let model = identity.map(ModelGrid.address(for:)) ?? "\(parts[1])/\(parts[2])"
            return BenchmarkRecord(
                backend: backend, model: model,
                quantization: quantization.serialised,
                identity: identity,
                language: corpus.language, metricKind: row.metricKind,
                errorRate: row.errorRate, rtf: row.rtf,
                peakMemoryGB: row.peakMemoryGB, audioDuration: corpus.duration,
                measuredAt: row.measuredAt,
                chip: machinesById[row.machineId]?.chip ?? "",
                macosVersion: row.macosVersion, appVersion: row.appVersion)
        }
        // One record per candidate per language (the old cache's key), so a
        // candidate never occupies multiple ranks and min-max normalization
        // stays honest (verify #14 M-5). #64: the collapse is an equal-weight
        // MEAN over the key's measurements (error rate and rtf), not
        // latest-wins — a single flattering short-corpus record can no longer
        // erase a candidate's broader history. The latest record is the field
        // template (measuredAt, versions). Deterministic order for stable
        // tie-breaks (L-19).
        var groups: [String: [BenchmarkRecord]] = [:]
        for record in projected {
            let key = "\(record.backend)|\(record.model)|\(record.quantization)|\(record.language)|\(record.chip)"
            groups[key, default: []].append(record)
        }
        let collapsed = groups.mapValues { group -> BenchmarkRecord in
            let latest = group.max { $0.measuredAt < $1.measuredAt }!
            guard group.count > 1 else { return latest }
            let meanError = group.map(\.errorRate).reduce(0, +) / Double(group.count)
            let meanTimesRealtime =
                group.map(\.timesRealtime).reduce(0, +) / Double(group.count)
            return BenchmarkRecord(
                backend: latest.backend, model: latest.model,
                quantization: latest.quantization,
                // Carried, not defaulted: dropping it here is what let a
                // candidate measured on several corpora be vouched for again
                // (round-4 verify C3).
                identity: latest.identity, language: latest.language,
                metricKind: latest.metricKind, errorRate: meanError,
                rtf: meanTimesRealtime > 0 ? 1.0 / meanTimesRealtime : 0,
                peakMemoryGB: latest.peakMemoryGB, audioDuration: latest.audioDuration,
                measuredAt: latest.measuredAt, chip: latest.chip,
                macosVersion: latest.macosVersion, appVersion: latest.appVersion)
        }
        return collapsed.sorted { $0.key < $1.key }.map(\.value)
    }
}
