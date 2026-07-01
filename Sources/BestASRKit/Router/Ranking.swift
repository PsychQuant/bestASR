import Foundation

/// Profile-weighted ranking over measured records — shared by the benchmark
/// report (spec benchmark: Rank candidates and report results) and the router
/// (spec asr-routing: Rank candidates by measured benchmark data).
///
/// Both axes are min-max normalized within the candidate set (a degenerate
/// axis where all values are equal scores 1 for everyone), then combined with
/// the profile's renormalized accuracy/speed weights. Locked to the spec SBE
/// tables: under `accurate` the low-CER candidate wins; under `fast` the same
/// measurements flip to the high-throughput candidate.
public enum Ranking {
    public struct Scored: Sendable {
        public let record: BenchmarkRecord
        public let score: Double
        public let rank: Int
    }

    public static func rank(_ records: [BenchmarkRecord], profile: RouterProfile) -> [Scored] {
        guard !records.isEmpty else { return [] }
        let errors = records.map(\.errorRate)
        let speeds = records.map(\.timesRealtime)
        let errorRange = (errors.min()!, errors.max()!)
        let speedRange = (speeds.min()!, speeds.max()!)

        func normalized(_ value: Double, low: Double, high: Double, invert: Bool) -> Double {
            guard high > low else { return 1.0 }
            let unit = (value - low) / (high - low)
            return invert ? 1.0 - unit : unit
        }

        let scored = records.map { record in
            let accuracy = normalized(
                record.errorRate, low: errorRange.0, high: errorRange.1, invert: true)
            let speed = normalized(
                record.timesRealtime, low: speedRange.0, high: speedRange.1, invert: false)
            return (record, profile.accuracyWeight * accuracy + profile.speedWeight * speed)
        }
        .sorted { $0.1 > $1.1 }

        return scored.enumerated().map { index, pair in
            Scored(record: pair.0, score: pair.1, rank: index + 1)
        }
    }
}
