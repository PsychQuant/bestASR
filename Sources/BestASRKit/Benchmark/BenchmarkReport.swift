import Foundation

/// Renders a benchmark outcome as the ranked human table or machine JSON
/// (spec benchmark: Rank candidates and report results).
public enum BenchmarkReport {
    public static func table(outcome: BenchmarkOutcome, profile: RouterProfile) -> String {
        var lines: [String] = []
        let metric = outcome.metricKind.rawValue.uppercased()

        if outcome.measured.isEmpty {
            lines.append("No candidate completed measurement.")
        } else {
            let ranked = Ranking.rank(outcome.measured.map(\.record), profile: profile)
            let warmupByKey = Dictionary(
                uniqueKeysWithValues: outcome.measured.map {
                    (BenchmarkCache.key($0.record), $0.warmupSeconds)
                })

            let header = [
                pad("RANK", 4), pad("BACKEND", 12), pad("MODEL", 16), pad("QUANT", 8),
                pad("\(metric)%", 7), pad("X-REAL", 7), pad("PEAK-GB", 8), pad("WARMUP-S", 8),
            ].joined(separator: "  ")
            lines.append(header)
            lines.append(String(repeating: "-", count: header.count))
            for scored in ranked {
                let record = scored.record
                let warmup = warmupByKey[BenchmarkCache.key(record)] ?? 0
                lines.append(
                    [
                        pad("\(scored.rank)", 4),
                        pad(record.backend, 12),
                        pad(record.model, 16),
                        pad(record.quantization, 8),
                        pad(String(format: "%.1f", record.errorRate * 100), 7),
                        pad(String(format: "%.1f", record.timesRealtime), 7),
                        pad(String(format: "%.2f", record.peakMemoryGB), 8),
                        pad(String(format: "%.1f", warmup), 8),
                    ].joined(separator: "  ")
                )
            }
            lines.append("")
            lines.append(
                "profile: \(profile.rawValue) · language: \(outcome.language) · metric: \(metric)"
            )
            lines.append(
                "peak-GB is an approximate process-footprint delta; warm-up (model "
                    + "download/load) is excluded from X-REAL."
            )
        }

        for note in outcome.notes {
            lines.append("note: \(note)")
        }
        for failure in outcome.failures {
            lines.append(
                "FAILED \(failure.candidate.backend.rawValue) \(failure.candidate.model) "
                    + "\(failure.candidate.quantization): \(failure.reason)"
            )
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON mode

    struct JSONRow: Codable {
        let rank: Int
        let backend: String
        let model: String
        let quantization: String
        let metric_kind: String
        let error_rate: Double
        let rtf: Double
        let times_realtime: Double
        let peak_memory_gb: Double
        let warmup_seconds: Double
    }

    struct JSONFailure: Codable {
        let backend: String
        let model: String
        let quantization: String
        let reason: String
    }

    struct JSONDocument: Codable {
        let profile: String
        let language: String
        let metric_kind: String
        let results: [JSONRow]
        let failures: [JSONFailure]
        let notes: [String]
    }

    public static func json(outcome: BenchmarkOutcome, profile: RouterProfile) throws -> String {
        let ranked = Ranking.rank(outcome.measured.map(\.record), profile: profile)
        let warmupByKey = Dictionary(
            uniqueKeysWithValues: outcome.measured.map {
                (BenchmarkCache.key($0.record), $0.warmupSeconds)
            })
        let document = JSONDocument(
            profile: profile.rawValue,
            language: outcome.language,
            metric_kind: outcome.metricKind.rawValue,
            results: ranked.map { scored in
                JSONRow(
                    rank: scored.rank,
                    backend: scored.record.backend,
                    model: scored.record.model,
                    quantization: scored.record.quantization,
                    metric_kind: scored.record.metricKind.rawValue,
                    error_rate: scored.record.errorRate,
                    rtf: scored.record.rtf,
                    times_realtime: scored.record.timesRealtime,
                    peak_memory_gb: scored.record.peakMemoryGB,
                    warmup_seconds: warmupByKey[BenchmarkCache.key(scored.record)] ?? 0
                )
            },
            failures: outcome.failures.map {
                JSONFailure(
                    backend: $0.candidate.backend.rawValue,
                    model: $0.candidate.model,
                    quantization: $0.candidate.quantization,
                    reason: $0.reason
                )
            },
            notes: outcome.notes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(document), as: UTF8.self)
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
