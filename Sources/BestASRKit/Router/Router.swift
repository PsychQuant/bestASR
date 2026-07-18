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
        // Runnable = whisper sizes plus live non-Whisper rows (#35); the
        // mlx-audio section stays a reference catalog with no bundled backend.
        let externalAvailable = availability[.mlxAudio] == true
        if let modelOverride,
            !ModelRegistry.isRunnableModel(modelOverride, includeExternal: externalAvailable) {
            throw BestASRError.usage(
                "unknown model: '\(modelOverride)'; run list-models for the "
                    + "runnable catalog (the mlx-audio section is a "
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

        // Availability, in preference order (spec: whisperkit first). Every
        // backend with a bundled engine enumerates (#35, spec asr-routing) —
        // the measured tier ranks across families; the cold-start prior below
        // still walks its whisper chain, so an unmeasured family is never
        // proposed without evidence.
        let availableOrdered: [BackendID] = [
            .whisperKit, .whisperCpp, .fluidParakeet, .fluidParaformer, .fluidSenseVoice,
            .mlxAudio,
        ].filter {
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
                // #105 declared-language gate — AUTONOMOUS ranking only. A
                // locked backend is the user's will and bypasses the gate
                // (same doctrine as the quality floor); the measured return
                // below still attaches a support warning in that case.
                && (requestedLanguage == nil || lockedBackend != nil
                    || Self.declaredSupport(
                        backend: record.backend, model: record.model, language: requestedLanguage!))
                && (modelOverride == nil || record.model == modelOverride)
        }

        // #64 (spec asr-routing): aggregate per candidate before ranking —
        // error rate / realtime factor become equal-weight means over the
        // candidate's usable records, so one flattering short-corpus record
        // can never outrank a broadly measured candidate.
        let aggregated = Self.aggregate(usable)
        // Quality floor: mean error rate above 0.5 has negative practical
        // value and is excluded from AUTONOMOUS ranking. A locked backend is
        // the user's will — it bypasses the floor with a warning; with no
        // lock an emptied pool falls through to the cold-start prior below.
        var pool = aggregated.filter { $0.record.errorRate <= Self.qualityFloor }
        if pool.isEmpty && !aggregated.isEmpty && lockedBackend != nil {
            pool = aggregated
            reasons.append(
                "quality floor bypassed: '\(lockedBackend!.rawValue)' is explicitly "
                    + "locked but its mean error rate exceeds \(Self.qualityFloor) — "
                    + "output quality is not established")
        }
        if let top = Ranking.rank(pool.map(\.record), profile: profile).first {
            let record = top.record
            guard let backend = BackendID(rawValue: record.backend) else {
                // `usable` already filtered unknown backends — this is
                // unreachable; failing loud beats silently mis-attributing
                // the record to whisperkit (#53 item 5).
                throw BestASRError.runtime(
                    "internal: ranked record carries unknown backend '\(record.backend)'")
            }
            // #105: a locked backend bypassed the declared-language gate to
            // get here — surface the support gap instead of staying silent.
            if let requestedLanguage,
                !Self.declaredSupport(
                    backend: record.backend, model: record.model, language: requestedLanguage) {
                warnings.append(
                    "backend '\(record.backend)' model '\(record.model)' does not list "
                        + "support for language '\(requestedLanguage)' — output quality "
                        + "is not established")
            }
            let percent = String(format: "%.1f", record.errorRate * 100)
            let speed = String(format: "%.1f", record.timesRealtime)
            reasons.append(
                "measured on this machine: \(record.metricKind.rawValue.uppercased()) "
                    + "\(percent)%, \(speed)x realtime "
                    + "(\(record.model), \(record.quantization); mean over this machine's measurements)"
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

        // A locked non-whisper backend has no rows for the whisper cold-start
        // sizes — fall back to the backend's own catalog instead of throwing
        // about a model the user never asked for (#35 verify H2: the natural
        // "benchmarked whisper, now try parakeet" first step must route).
        if modelOverride == nil,
            ModelRegistry.quantizations(for: backend, model: model).isEmpty,
            let catalogFallback = ModelGrid.rows(
                backend: backend.rawValue, priorityCeiling: nil
            ).first?.size {
            reasons.append(
                "cold-start prior has no '\(model)' on \(backend.rawValue); "
                    + "using its catalog model '\(catalogFallback)'")
            if let row = ModelGrid.rows(backend: backend.rawValue, priorityCeiling: nil)
                .first(where: { $0.size == catalogFallback }), !row.verified {
                reasons.append(
                    "warning: '\(catalogFallback)' on \(backend.rawValue) is unverified "
                        + "on this machine — quality is not established (#50)")
            }
            model = catalogFallback
        }

        // #105 declared-language check on the cold-start outcome: a locked or
        // prior-selected backend whose catalog row does not advertise the
        // target language ships with an explicit warning, never silently.
        if let requestedLanguage,
            !Self.declaredSupport(
                backend: backend.rawValue, model: model, language: requestedLanguage) {
            warnings.append(
                "backend '\(backend.rawValue)' model '\(model)' does not list support "
                    + "for language '\(requestedLanguage)' — output quality is not established")
        }

        // A model address only pairs with backends whose grid lists variants
        // for it (#14; explicit mismatches like --backend whisperkit
        // --model 0.6b-v3 still fail loud here).
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

    /// #105 declared-language gate: with a known target language, a model
    /// whose catalog row advertises neither that language nor "multi" is not
    /// an autonomous candidate (parakeet's European-only row must never rank
    /// for zh). Models outside the grid fail open — the grid only catalogs
    /// non-whisper backends, and whisper sizes are multilingual by
    /// construction.
    static func declaredSupport(backend: String, model: String, language: String) -> Bool {
        guard
            let row = ModelGrid.rows(backend: backend, priorityCeiling: nil)
                .first(where: { $0.size == model })
        else { return true }
        let base = LanguageResolver.baseSubtag(language)
        return row.languages.contains {
            $0 == "multi" || LanguageResolver.baseSubtag($0) == base
        }
    }

    /// #64 (spec asr-routing): equal-weight per-record mean per candidate
    /// (backend, model, quantization). The synthesized record carries the
    /// means with the latest record as the field template; `runs` feeds the
    /// aggregation disclosure in the reasons.
    static let qualityFloor = 0.5

    static func aggregate(_ records: [BenchmarkRecord]) -> [(record: BenchmarkRecord, runs: Int)] {
        let groups = Dictionary(grouping: records) {
            // language in the key (#64 verify F1): a nil-language query sees
            // per-language rows — averaging WER(en) with CER(zh) is
            // physically meaningless and could false-trip the quality floor.
            "\($0.backend)|\($0.model)|\($0.quantization)|\($0.language)"
        }
        return groups.values.map { group in
            let latest = group.max { $0.measuredAt < $1.measuredAt }!
            let meanError = group.map(\.errorRate).reduce(0, +) / Double(group.count)
            let meanTimesRealtime =
                group.map(\.timesRealtime).reduce(0, +) / Double(group.count)
            let record = BenchmarkRecord(
                backend: latest.backend, model: latest.model,
                quantization: latest.quantization, language: latest.language,
                metricKind: latest.metricKind, errorRate: meanError,
                rtf: meanTimesRealtime > 0 ? 1.0 / meanTimesRealtime : 0,
                peakMemoryGB: latest.peakMemoryGB, audioDuration: latest.audioDuration,
                measuredAt: latest.measuredAt, chip: latest.chip,
                macosVersion: latest.macosVersion, appVersion: latest.appVersion)
            return (record, group.count)
        }
    }
}
