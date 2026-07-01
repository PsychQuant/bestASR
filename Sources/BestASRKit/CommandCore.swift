import Foundation

/// The outcome of a `transcribe` invocation, for the CLI to report.
public struct TranscribeOutcome: Sendable {
    public let outputPath: String
    public let format: String
    public let explanation: String

    public init(outputPath: String, format: String, explanation: String) {
        self.outputPath = outputPath
        self.format = format
        self.explanation = explanation
    }
}

/// Library-side command handlers (design D1: the executable is a thin
/// argument-parsing shell; every behavior lives here where tests can reach it).
public struct CommandCore: Sendable {
    public let engines: [any Engine]
    let detect: @Sendable () throws -> SystemInfo
    let cache: BenchmarkCache
    let probe: MeasurementProbe

    public init(
        engines: [any Engine],
        detect: @escaping @Sendable () throws -> SystemInfo = { try SystemDetector.detect() },
        cache: BenchmarkCache = .live(),
        probe: MeasurementProbe = .live()
    ) {
        self.engines = engines
        self.detect = detect
        self.cache = cache
        self.probe = probe
    }

    /// The production wiring: real engines, real detection, real cache.
    public static func live() -> CommandCore {
        CommandCore(engines: [WhisperKitEngine(), WhisperCppEngine()])
    }

    func availability() async -> [BackendID: Bool] {
        var result: [BackendID: Bool] = [:]
        for engine in engines {
            result[engine.id] = await engine.isAvailable()
        }
        return result
    }

    // MARK: - diagnose (spec cli: diagnose command)

    public func diagnose() async throws -> String {
        let host = try detect()
        var lines = [
            "System:",
            "  Chip:           \(host.chip)",
            "  Unified memory: \(String(format: "%.1f", host.unifiedMemoryGB)) GB",
            "  Neural Engine:  \(host.hasANE == true ? "yes" : host.hasANE == false ? "no" : "unknown")",
            "  macOS:          \(host.macosVersion)",
            "",
            "Recommendation:",
        ]
        do {
            let rec = try Router.recommend(
                host: host, profile: .balanced, requestedLanguage: nil,
                backendOverride: nil, modelOverride: nil,
                records: try cache.load(), availability: await availability()
            )
            lines += [
                "  Backend:      \(rec.backend.rawValue)",
                "  Model:        \(rec.model)",
                "  Quantization: \(rec.quantization)",
                "  Data source:  \(rec.dataSource.rawValue)",
                "Reason:",
            ]
            lines += rec.reason.map { "  - \($0)" }
            lines += rec.warnings.map { "  ! \($0)" }
        } catch let error as BestASRError {
            // diagnose still reports the environment when no backend is usable.
            lines.append("  \(error.errorDescription ?? "unavailable")")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - recommend (spec cli: recommend command emits JSON only)

    struct RecommendationJSON: Codable {
        let backend: String
        let model: String
        let quantization: String
        let profile: String
        let language: String?
        let data_source: String
        let measured: MeasuredJSON?
        let reason: [String]
        let warnings: [String]

        struct MeasuredJSON: Codable {
            let metric_kind: String
            let error_rate: Double
            let rtf: Double
        }
    }

    func resolveRecommendation(
        selection: SelectionRequest, language: String?
    ) async throws -> ASRRecommendation {
        guard let profile = RouterProfile(rawValue: selection.profileName.lowercased()) else {
            throw BestASRError.usage(
                "unknown profile: '\(selection.profileName)'; supported profiles are "
                    + RouterProfile.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }
        return try Router.recommend(
            host: try detect(),
            profile: profile,
            requestedLanguage: language,
            backendOverride: selection.backendOverride,
            modelOverride: selection.modelOverride,
            records: try cache.load(),
            availability: await availability()
        )
    }

    public func recommendJSON(audioPath: String, selection: SelectionRequest) async throws -> String {
        let audio = try AudioProber.probe(
            path: audioPath, requestedLanguage: selection.requestedLanguage)
        let rec = try await resolveRecommendation(selection: selection, language: audio.language)
        let document = RecommendationJSON(
            backend: rec.backend.rawValue,
            model: rec.model,
            quantization: rec.quantization,
            profile: rec.profile.rawValue,
            language: rec.language,
            data_source: rec.dataSource.rawValue,
            measured: rec.measured.map {
                .init(metric_kind: $0.metricKind.rawValue, error_rate: $0.errorRate, rtf: $0.rtf)
            },
            reason: rec.reason,
            warnings: rec.warnings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(document), as: UTF8.self)
    }

    // MARK: - transcribe (spec cli: transcribe command with options, explain mode)

    public func transcribe(
        audioPath: String,
        selection: SelectionRequest,
        formatName: String,
        outputPath: String?
    ) async throws -> TranscribeOutcome {
        let format = try TranscriptWriter.format(named: formatName)
        let audio = try AudioProber.probe(
            path: audioPath, requestedLanguage: selection.requestedLanguage)
        let rec = try await resolveRecommendation(selection: selection, language: audio.language)
        guard let engine = engines.first(where: { $0.id == rec.backend }) else {
            throw BestASRError.runtime("no engine registered for backend \(rec.backend.rawValue)")
        }

        let transcript = try await engine.transcribe(
            audioPath: audio.path,
            options: TranscribeOptions(
                model: rec.model, quantization: rec.quantization, language: audio.language)
        )

        let destination = outputPath ?? Self.derivedOutputPath(audioPath: audioPath, format: format)
        try TranscriptWriter.write(transcript, to: destination, format: format)

        var explanation = [
            "Selected \(rec.backend.rawValue) \(rec.model) (\(rec.quantization)) "
                + "[\(rec.dataSource.rawValue)] because:"
        ]
        explanation += rec.reason.map { "  - \($0)" }
        explanation += rec.warnings.map { "  ! \($0)" }
        return TranscribeOutcome(
            outputPath: destination,
            format: format.rawValue,
            explanation: explanation.joined(separator: "\n")
        )
    }

    static func derivedOutputPath(audioPath: String, format: OutputFormat) -> String {
        let url = URL(fileURLWithPath: audioPath)
        return url.deletingPathExtension().appendingPathExtension(format.rawValue).path
    }

    // MARK: - benchmark (spec cli: benchmark command)

    public func benchmark(
        audioPath: String,
        referencePath: String,
        language: String,
        backendFilter: [String]?,
        modelFilter: [String]?,
        profileName: String,
        asJSON: Bool
    ) async throws -> String {
        guard let profile = RouterProfile(rawValue: profileName.lowercased()) else {
            throw BestASRError.usage(
                "unknown profile: '\(profileName)'; supported profiles are "
                    + RouterProfile.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }

        // Reference problems are usage errors raised BEFORE any transcription.
        let cues = try SRTParser.parse(fileAt: referencePath)
        let referenceText = SRTParser.referenceText(from: cues)

        let resolvedLanguage = LanguageResolver.resolve(language)
        let metricKind =
            resolvedLanguage.map(LanguageResolver.metricKind(forLanguage:))
            ?? LanguageResolver.metricKind(inferredFromReference: referenceText)

        let audio = try AudioProber.probe(path: audioPath, requestedLanguage: language)
        let host = try detect()
        let runner = BenchmarkRunner(engines: engines, host: host, probe: probe)

        let enumeration = try await runner.enumerateCandidates(
            backendFilter: backendFilter, modelFilter: modelFilter)
        guard !enumeration.candidates.isEmpty else {
            throw BestASRError.runtime(
                "no benchmark candidates: "
                    + (enumeration.notes.isEmpty
                        ? "no backend matched the filters"
                        : enumeration.notes.joined(separator: "; "))
            )
        }

        let outcome = await runner.run(
            candidates: enumeration.candidates,
            notes: enumeration.notes,
            audio: audio,
            referenceText: referenceText,
            metricKind: metricKind,
            language: resolvedLanguage ?? "auto"
        )

        if !outcome.measured.isEmpty {
            try cache.upsert(outcome.measured.map(\.record))
        }

        let report =
            asJSON
            ? try BenchmarkReport.json(outcome: outcome, profile: profile)
            : BenchmarkReport.table(outcome: outcome, profile: profile)

        guard !outcome.measured.isEmpty else {
            // Every candidate failed — runtime failure carrying the report so
            // the caller still sees what happened (spec: warn-continue).
            throw BestASRError.runtime("all benchmark candidates failed\n\(report)")
        }
        return report
    }

    // MARK: - list-* (spec cli: list-backends and list-models)

    public func listBackends() async -> String {
        var lines: [String] = []
        for engine in engines {
            let status = await engine.isAvailable() ? "available" : "not installed"
            lines.append("\(engine.id.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)) \(status)")
        }
        return lines.joined(separator: "\n")
    }

    public func listModels() -> String {
        ModelRegistry.supportedModels.map { model in
            let quants = BackendID.allCases.compactMap { backend -> String? in
                guard let variants = ModelRegistry.quantizations[backend] else { return nil }
                return "\(backend.rawValue): \(variants.joined(separator: "/"))"
            }
            return "\(model.padding(toLength: 16, withPad: " ", startingAt: 0)) (\(quants.joined(separator: " · ")))"
        }
        .joined(separator: "\n")
    }
}
