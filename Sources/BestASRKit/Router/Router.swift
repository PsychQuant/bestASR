import Foundation

/// Two-tier router (design D2): measured benchmark ranking first, cold-start
/// prior fallback — every recommendation explainable (spec asr-routing).
public enum Router {
    static let installGuidance =
        "install whisperkit models on demand (bundled) and whisper.cpp with: brew install whisper-cpp"

    public static func recommend(
        host: SystemInfo,
        profile: RouterProfile,
        requestedLanguage: String?,
        backendOverride: String?,
        modelOverride: String?,
        records: [BenchmarkRecord],
        availability: [BackendID: Bool]
    ) throws -> ASRRecommendation {
        var reasons: [String] = []
        var warnings: [String] = []

        // Validate overrides early (usage errors, not silent acceptance).
        if let modelOverride, !ModelRegistry.isSupportedModel(modelOverride) {
            throw BestASRError.usage(
                "unknown model: '\(modelOverride)'; run list-models for the "
                    + "runnable catalog (whisper sizes — the mlx-audio section is a "
                    + "reference catalog with no bundled backend)"
            )
        }
        let overrideBackend: BackendID? = try backendOverride.map { name in
            guard let id = BackendID(rawValue: name.lowercased()) else {
                throw BestASRError.usage(
                    "unknown backend: '\(name)'; supported backends are "
                        + BackendID.allCases.map(\.rawValue).joined(separator: ", ")
                )
            }
            return id
        }

        // Availability, in preference order (spec: whisperkit first).
        let availableOrdered: [BackendID] = [.whisperKit, .whisperCpp].filter {
            availability[$0] == true
        }
        guard !availableOrdered.isEmpty else {
            throw BestASRError.runtime(
                "no ASR backend is available; supported backends: "
                    + BackendID.allCases.map(\.rawValue).joined(separator: ", ")
                    + ". \(installGuidance)"
            )
        }

        // Explicit backend override with fallback (spec asr-routing).
        var lockedBackend: BackendID? = nil
        if let overrideBackend {
            if availableOrdered.contains(overrideBackend) {
                lockedBackend = overrideBackend
                reasons.append("backend '\(overrideBackend.rawValue)' explicitly requested")
            } else {
                warnings.append(
                    "requested backend '\(overrideBackend.rawValue)' is unavailable; "
                        + "selecting automatically"
                )
            }
        }

        // Tier 1 — measured ranking (spec: Rank candidates by measured benchmark data).
        let usable = records.filter { record in
            record.chip == host.chip
                && BackendID(rawValue: record.backend).map { backend in
                    availableOrdered.contains(backend)
                        && (lockedBackend == nil || backend == lockedBackend)
                } == true
                && (requestedLanguage == nil || record.language == requestedLanguage)
                && (modelOverride == nil || record.model == modelOverride)
        }

        if let top = Ranking.rank(usable, profile: profile).first {
            let record = top.record
            let backend = BackendID(rawValue: record.backend) ?? .whisperKit
            let percent = String(format: "%.1f", record.errorRate * 100)
            let speed = String(format: "%.1f", record.timesRealtime)
            reasons.append(
                "measured on this machine: \(record.metricKind.rawValue.uppercased()) "
                    + "\(percent)%, \(speed)x realtime (\(record.model), \(record.quantization))"
            )
            reasons.append(
                "ranked #1 of \(usable.count) benchmarked candidate(s) under the "
                    + "'\(profile.rawValue)' profile"
            )
            return ASRRecommendation(
                backend: backend,
                model: record.model,
                quantization: record.quantization,
                profile: profile,
                language: requestedLanguage,
                dataSource: .measured,
                measured: MeasuredSummary(
                    metricKind: record.metricKind,
                    errorRate: record.errorRate,
                    rtf: record.rtf
                ),
                reason: reasons,
                warnings: warnings
            )
        }

        // Tier 2 — cold-start prior (spec: Cold-start prior when no benchmark data exists).
        let backend: BackendID
        if let lockedBackend {
            backend = lockedBackend
        } else {
            let choice = ColdStartPrior.selectBackend(
                available: availableOrdered, hasANE: host.hasANE)
            backend = choice.backend
            reasons += choice.reasons
        }

        var model: String
        if let modelOverride {
            reasons.append("model '\(modelOverride)' explicitly requested")
            let (fitted, downgradeWarnings, downgradeReasons) = ColdStartPrior.ensureFits(
                modelOverride, in: host.unifiedMemoryGB)
            model = fitted
            warnings += downgradeWarnings
            reasons += downgradeReasons
        } else {
            let choice = ColdStartPrior.selectModel(
                profile: profile, unifiedMemoryGB: host.unifiedMemoryGB)
            model = choice.model
            reasons += choice.reasons
            warnings += choice.warnings
        }

        reasons.append(
            "cold start — run 'bestasr benchmark <audio> --reference <truth.srt>' for "
                + "measured, machine-specific recommendations"
        )

        // A model address only pairs with backends whose grid lists variants
        // for it (#14; since #20 only the whisper backends are runnable).
        guard let quantization = ModelRegistry.quantizations(for: backend, model: model).first
        else {
            throw BestASRError.usage(
                "model '\(model)' is not available on backend \(backend.rawValue); "
                    + "run list-models for the catalog")
        }
        return ASRRecommendation(
            backend: backend,
            model: model,
            quantization: quantization,
            profile: profile,
            language: requestedLanguage,
            dataSource: .coldStartPrior,
            measured: nil,
            reason: reasons,
            warnings: warnings
        )
    }
}
