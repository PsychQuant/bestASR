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
    let store: BenchmarkStore
    let diarizer: @Sendable (String) async throws -> DiarizationOutput
    let enroller: @Sendable (String) async throws -> [Float]?
    let dynamicHost: @Sendable () -> DynamicHostState
    let probe: MeasurementProbe

    public init(
        engines: [any Engine],
        detect: @escaping @Sendable () throws -> SystemInfo = { try SystemDetector.detect() },
        store: BenchmarkStore = BenchmarkStore(),
        probe: MeasurementProbe = .live(),
        diarizer: @escaping @Sendable (String) async throws -> DiarizationOutput = {
            try await DiarizationEngine().diarize(audioPath: $0)
        },
        enroller: @escaping @Sendable (String) async throws -> [Float]? = {
            try await SpeakerEnroller().embedding(for: $0)
        },
        dynamicHost: @escaping @Sendable () -> DynamicHostState = { .probe() }
    ) {
        self.engines = engines
        self.detect = detect
        self.store = store
        self.diarizer = diarizer
        self.enroller = enroller
        self.dynamicHost = dynamicHost
        self.probe = probe
    }

    /// The production wiring: real engines, real detection, real store.
    public static func live() -> CommandCore {
        {
        // Registered external adapters (#51, spec external-engine-protocol)
        // join the pool next to the bundled engines; with no registry config
        // this is exactly the bundled set.
        var engines: [any Engine] = [
            WhisperKitEngine(), WhisperCppEngine(), ParakeetEngine(),
            ChineseFamilyEngine.paraformer(), ChineseFamilyEngine.sensevoice(),
        ]
        for entry in ExternalEngineRegistry().engines {
            engines.append(ExternalProcessEngine(id: entry.id, command: entry.command))
        }
        return CommandCore(engines: engines)
    }()
    }

    /// Store-projected records for the router (design D7).
    func loadRecords() throws -> [BenchmarkRecord] {
        try store.load().projectedRecords()
    }

    func availability() async -> [BackendID: Bool] {
        var result: [BackendID: Bool] = [:]
        for engine in engines {
            result[engine.id] = await engine.isAvailable()
        }
        return result
    }

    // MARK: - Context (spec context-calibration; design D1/D4/D9)

    struct ContextBundle {
        let loaded: LoadedContext
        let rendered: PromptRenderer.Rendered
    }

    /// Resolve + load + render. Returns nil when nothing resolves or the
    /// directory holds neither values nor ignorable files — zero impact.
    /// A directory that only holds unsupported files still returns a bundle
    /// (prompt nil) so the ignore list is disclosed loudly, never silently.
    func loadContext(flag: String?) throws -> ContextBundle? {
        guard let loaded = try ContextLoader.load(flag: flag) else { return nil }
        if loaded.isEmpty && loaded.ignoredFiles.isEmpty { return nil }
        return ContextBundle(loaded: loaded, rendered: PromptRenderer.render(loaded))
    }

    /// Grid-row lookup for a measured candidate (#16): keyed by the facts the
    /// benchmark record actually carries — backend, size, quantization — so the
    /// row's own family (and pin) travel back without a hardcoded key.
    static func seededRow(
        in rows: [ModelRow], backend: String, size: String, quantization: String
    ) -> ModelRow? {
        rows.first {
            $0.backend == backend && $0.size == size && $0.quantization == quantization
        }
    }

    static func contextReasonLine(_ bundle: ContextBundle) -> String {
        if bundle.rendered.injected.isEmpty {
            return "context: \(bundle.loaded.directory) — 0 values injected; "
                + "\(bundle.loaded.ignoredFiles.count) file(s) ignored (run the context-ingest skill)"
        }
        return "context: \(bundle.loaded.directory) — \(bundle.rendered.injected.count) value(s) injected"
    }

    /// Explain-mode disclosure (design D9): resolved dir, injected values,
    /// truncated items, ignored files with ingestion guidance.
    static func contextExplanation(_ bundle: ContextBundle) -> [String] {
        var lines = ["Context: \(bundle.loaded.directory)"]
        lines.append(
            "  injected (\(bundle.rendered.injected.count)): "
                + (bundle.rendered.injected.isEmpty
                    ? "(none)" : bundle.rendered.injected.joined(separator: ", ")))
        if !bundle.rendered.truncated.isEmpty {
            lines.append(
                "  truncated (\(bundle.rendered.truncated.count)): "
                    + bundle.rendered.truncated.joined(separator: ", "))
        }
        for file in bundle.loaded.ignoredFiles {
            lines.append("  ignored: \(file) — \(LoadedContext.ingestGuidance)")
        }
        return lines
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
            // Resolve the same way transcribe/recommend do, so diagnose's
            // "what would it recommend?" tells the truth under machine pressure
            // (#29 verify #1/#9/#10/#14 — one source of truth for the default).
            let resolved = try Self.resolveProfile(named: "auto", dynamicState: dynamicHost())
            let rec = try Router.recommend(
                host: host, profile: resolved.profile, requestedLanguage: nil,
                backendOverride: nil, modelOverride: nil,
                records: try loadRecords(), availability: await availability()
            ).prepending(reasons: resolved.reasons)
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

    /// Parse an explicit ordinal profile. Legacy names fail with their
    /// ordinal replacement (spec cli: legacy profile values fail with a
    /// migration hint, #29 — the user ruled out an alias layer).
    static func parseProfile(_ name: String) throws -> RouterProfile {
        let lowered = name.lowercased()
        if let profile = RouterProfile(rawValue: lowered) { return profile }
        let migrations = [
            "fast": "low", "balanced": "medium",
            "accurate": "high (or max for accuracy at any cost)",
        ]
        if let replacement = migrations[lowered] {
            throw BestASRError.usage(
                "profile '\(lowered)' was renamed — use '\(replacement)'; profiles are now "
                    + RouterProfile.allCases.map(\.rawValue).joined(separator: ", "))
        }
        // Note: `auto` is NOT listed here — it is intercepted by resolveProfile
        // before this function, and benchmark (the other caller) does not accept
        // it. Advertising auto here contradicted `benchmark --profile auto` (#29
        // verify #2/#3).
        throw BestASRError.usage(
            "unknown profile: '\(name)'; supported profiles are "
                + RouterProfile.allCases.map(\.rawValue).joined(separator: ", "))
    }

    /// Resolve the CLI profile string. `auto` (the transcribe/recommend
    /// default) adapts to dynamic machine conditions — medium normally, low
    /// under thermal/power pressure — and says so in the explain reasons.
    /// An explicit ordinal is never altered by machine state (spec cli, #29).
    static func resolveProfile(
        named name: String, dynamicState: DynamicHostState
    ) throws -> (profile: RouterProfile, reasons: [String]) {
        guard name.lowercased() == "auto" else {
            return (try parseProfile(name), [])
        }
        if let cause = dynamicState.pressureCause {
            return (.low, ["auto profile downshifted to low (\(cause))"])
        }
        return (.medium, ["auto profile resolved to medium (no machine pressure)"])
    }

    func resolveRecommendation(
        selection: SelectionRequest, language: String?
    ) async throws -> ASRRecommendation {
        let resolved = try Self.resolveProfile(
            named: selection.profileName, dynamicState: dynamicHost())
        let rec = try Router.recommend(
            host: try detect(),
            profile: resolved.profile,
            requestedLanguage: language,
            backendOverride: selection.backendOverride,
            modelOverride: selection.modelOverride,
            records: try loadRecords(),
            availability: await availability()
        )
        return rec.prepending(reasons: resolved.reasons)
    }

    public func recommendJSON(audioPath: String, selection: SelectionRequest) async throws -> String {
        let audio = try AudioProber.probe(
            path: audioPath, requestedLanguage: selection.requestedLanguage)
        var rec = try await resolveRecommendation(selection: selection, language: audio.language)
        if let bundle = try loadContext(flag: selection.contextDir) {
            rec = ASRRecommendation(
                backend: rec.backend, model: rec.model, quantization: rec.quantization,
                profile: rec.profile, language: rec.language, dataSource: rec.dataSource,
                measured: rec.measured,
                reason: rec.reason + [Self.contextReasonLine(bundle)],
                warnings: rec.warnings
            )
        }
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
        outputPath: String?,
        diarize: Bool = false,
        hallucinationFilter: HallucinationFilterMode = .denylist,
        noSpeechThreshold: Double? = nil,
        compressionRatioThreshold: Double? = nil,
        logProbThreshold: Double? = nil
    ) async throws -> TranscribeOutcome {
        let format = try TranscriptWriter.format(named: formatName)
        let audio = try AudioProber.probe(
            path: audioPath, requestedLanguage: selection.requestedLanguage)
        let rec = try await resolveRecommendation(selection: selection, language: audio.language)
        guard let engine = engines.first(where: { $0.id == rec.backend }) else {
            throw BestASRError.runtime("no engine registered for backend \(rec.backend.rawValue)")
        }

        let context = try loadContext(flag: selection.contextDir)
        let transcript = try await engine.transcribe(
            audioPath: audio.path,
            options: TranscribeOptions(
                model: rec.model, quantization: rec.quantization,
                language: audio.language, prompt: context?.rendered.prompt,
                noSpeechThreshold: noSpeechThreshold,
                compressionRatioThreshold: compressionRatioThreshold,
                logProbThreshold: logProbThreshold)
        )

        // Cue-level diarization (#25, spec diarization): acoustic turns from the
        // FluidAudio pipeline, assigned to segments by max time overlap. Runs
        // after transcription — fail-loud per design D4 (an explicitly requested
        // capability must not silently disappear from the output).
        var finalTranscript = transcript
        var identificationNote: String?
        if diarize {
            // Speaker identification (#26): enrollment voices under the resolved
            // context dir's voices/ folder become known speakers, so matching
            // turns come back labeled by name. Resolved independently of the
            // prompt context (a dir with ONLY voices/ is "empty" to loadContext
            // but still enrolls). voices absent → pure #25 diarization.
            var enrolled: [(name: String, embedding: [Float])] = []
            var enrollWarnings: [String] = []
            // Resolved independently of the prompt context (a dir with ONLY
            // voices/ is "empty" to loadContext but still enrolls); a directory
            // read error surfaces as no voices rather than aborting.
            let voices = (try? ContextLoader.load(flag: selection.contextDir))?.voices ?? []
            for voice in voices {
                // An enrollment named like an ordinal (SPEAKER_3.wav) would
                // collide with a stranger's auto-label — warn, still enroll (#26 verify).
                if voice.label.range(of: #"^SPEAKER_\d+$"#, options: .regularExpression) != nil {
                    enrollWarnings.append(
                        "voice '\(voice.label)' looks like an auto-ordinal — rename to avoid confusion with unenrolled speakers")
                }
                // Per-voice warn-continue (#26 verify): one unreadable/corrupt
                // enrollment sample must not abort the whole transcription.
                do {
                    if let embedding = try await enroller(voice.path) {
                        enrolled.append((name: voice.label, embedding: embedding))
                    } else {
                        enrollWarnings.append("voice '\(voice.label)' yielded no usable embedding (too short/silent)")
                    }
                } catch {
                    enrollWarnings.append("voice '\(voice.label)' failed to enroll: \(error.localizedDescription)")
                }
            }
            let output = try await diarizer(audio.path)
            // Post-hoc identification (#26): map raw diarization ids to enrolled
            // names by embedding distance, then relabel the turns before
            // assignment. Unmatched ids keep their raw id → SPEAKER_N ordinal.
            let idToName = SpeakerIdentifier.resolve(
                embeddings: output.embeddings, enrolled: enrolled)
            let namedTurns = output.turns.map { turn in
                idToName[turn.speaker].map {
                    SpeakerTurn(speaker: $0, start: turn.start, end: turn.end)
                } ?? turn
            }
            let knownNames = Set(idToName.values)
            let labels = SpeakerAssigner.assign(
                segments: transcript.segments, turns: namedTurns, knownNames: knownNames)
            if !voices.isEmpty {
                // "enrolled" counts embeddings actually obtained, not files found;
                // "matched" counts distinct enrolled names hit. When more raw
                // speakers than names matched, several acoustic clusters collapsed
                // onto one name — usually one over-segmented person (design D6),
                // but surfaced (not hidden by the Set dedup) so a genuine
                // two-people-one-name misattribution is visible (#26 verify).
                identificationNote =
                    "voices: \(enrolled.count)/\(voices.count) enrolled, "
                    + "\(knownNames.count) name(s) matched across \(idToName.count) diarized speaker(s)"
                    + enrollWarnings.map { "\n  ! \($0)" }.joined()
            }
            // D4 fail-loud covers the SOFT failure too: an engine that
            // "succeeds" with zero usable turns would emit output
            // indistinguishable from --diarize never being passed.
            guard transcript.segments.isEmpty || labels.contains(where: { $0 != nil }) else {
                throw BestASRError.runtime(
                    "diarization yielded no speaker for any segment — refusing to emit "
                        + "unlabeled output for an explicit --diarize (check the audio, or "
                        + "run without --diarize)")
            }
            finalTranscript = Transcript(
                text: transcript.text, language: transcript.language,
                duration: transcript.duration, backend: transcript.backend,
                model: transcript.model,
                segments: zip(transcript.segments, labels).map { $0.withSpeaker($1) })
        }

        // Strip decoder hallucinations (silent-segment boilerplate, empty /
        // duplicate cues) before writing. Backend-agnostic and post-diarization,
        // so speaker labels on surviving cues are preserved (#98).
        finalTranscript = HallucinationFilter.filter(finalTranscript, mode: hallucinationFilter)

        let destination = outputPath ?? Self.derivedOutputPath(audioPath: audioPath, format: format)
        try TranscriptWriter.write(finalTranscript, to: destination, format: format)

        var explanation = [
            "Selected \(rec.backend.rawValue) \(rec.model) (\(rec.quantization)) "
                + "[\(rec.dataSource.rawValue)] because:"
        ]
        explanation += rec.reason.map { "  - \($0)" }
        explanation += rec.warnings.map { "  ! \($0)" }
        if let context {
            explanation += Self.contextExplanation(context)
        }
        if let identificationNote {
            explanation.append("  \(identificationNote)")
        }
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
        asJSON: Bool,
        contextDir: String? = nil,
        allGrid: Bool = false,
        decodeDeterministic: Bool = false
    ) async throws -> String {
        let profile = try Self.parseProfile(profileName)

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
            backendFilter: backendFilter, modelFilter: modelFilter, allGrid: allGrid)
        guard !enumeration.candidates.isEmpty else {
            throw BestASRError.runtime(
                "no benchmark candidates: "
                    + (enumeration.notes.isEmpty
                        ? "no backend matched the filters"
                        : enumeration.notes.joined(separator: "; "))
            )
        }

        // ±context delta mode (spec benchmark; design D6): context is loaded
        // via the same three-layer resolution; the runner measures a second
        // with-context pass per candidate while the cache stays baseline-only.
        let contextBundle = try loadContext(flag: contextDir)
        let outcome = await runner.run(
            candidates: enumeration.candidates,
            notes: enumeration.notes
                + (contextBundle.map {
                    ["context: \($0.loaded.directory) — "
                     + "\($0.rendered.injected.count) value(s) in the with-context pass"]
                } ?? []),
            audio: audio,
            referenceText: referenceText,
            metricKind: metricKind,
            language: resolvedLanguage ?? "auto",
            contextPrompt: contextBundle?.rendered.prompt,
            deterministicDecode: decodeDeterministic
        )

        if !outcome.measured.isEmpty {
        // Persist to the BCNF store (spec benchmark: append-only measurements);
        // the grid seed keeps the models table code-owned and current.
        try store.seed(models: ModelGrid.rows)
        let machine = MachineRow(chip: host.chip, unifiedMemoryGB: host.unifiedMemoryGB)
        try store.upsert(machine: machine)
        // Registered corpus metadata is authoritative — benchmark only fills
        // rows for corpora it created and never clobbers name/language set via
        // corpus add (verify #14 M-3/M-4).
        let audioHash = try fileSHA256(URL(fileURLWithPath: audio.path))
        let existing = try store.load().corpora.first { $0.audioSHA256 == audioHash }
        let corpus = CorpusRow(
            name: existing?.name
                ?? URL(fileURLWithPath: audio.path).deletingPathExtension().lastPathComponent,
            language: existing?.language ?? resolvedLanguage ?? "auto",
            audioSHA256: audioHash,
            referenceSHA256: try fileSHA256(URL(fileURLWithPath: referencePath)),
            duration: audio.duration ?? existing?.duration ?? 0,
            audioPath: audio.path, referencePath: referencePath)
        try store.upsert(corpus: corpus)
        // Pin provenance (#16): resolve each measurement's grid row — and with
        // it the hf_revision pin AND the true modelId (family included) — from
        // the rows seeded for THIS run. ModelGrid.rows was seeded verbatim a few
        // lines above, so the in-memory array IS the as-seeded table (no store
        // re-read; #16 verify F12). Matching by (backend, size, quantization)
        // instead of a hardcoded family="whisper" key keeps the measurement's
        // PRIMARY KEY honest for non-whisper families (#16 verify DA).
        for measured in outcome.measured {
            let record = measured.record
            // record.model is an ADDRESS for mlx-audio (family/size, #65) —
            // resolve through the same helper as the read side, or the
            // persisted modelId mangles to 'whisper|family/size' and the
            // revision pin is lost (verify F1).
            let seededRow = ModelGrid.row(
                backend: record.backend, modelAddress: record.model)
                .flatMap { row in
                    ModelGrid.rows.first {
                        $0.backend == row.backend && $0.family == row.family
                            && $0.size == row.size
                            && $0.quantization == record.quantization
                    }
                }
            let modelId = seededRow?.modelId ?? ModelRow.id(
                backend: record.backend, family: "whisper", size: record.model,
                quantization: record.quantization)
            try store.append(measurement: MeasurementRow(
                modelId: modelId,
                corpusId: corpus.corpusId, machineId: machine.machineId,
                measuredAt: record.measuredAt, metricKind: record.metricKind,
                errorRate: record.errorRate, rtf: record.rtf,
                peakMemoryGB: record.peakMemoryGB, warmupSeconds: measured.warmupSeconds,
                appVersion: record.appVersion, macosVersion: record.macosVersion,
                contextErrorRate: measured.contextErrorRate,
                hfRevision: seededRow?.hfRevision))
        }
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
        var lines: [String] = []
        let whisperBackends = [ModelGrid.backendWhisperKit, ModelGrid.backendWhisperCpp]
        for (size, _) in ModelGrid.whisperSizes {
            // Whisper sizes list whisper-family backends only — a same-named
            // size on another family (sensevoice "small", #50 verify H1) must
            // not masquerade as a whisper variant.
            let quants = whisperBackends.compactMap { backend -> String? in
                let variants = ModelGrid.rows.filter {
                    $0.backend == backend && $0.size == size
                }.map(\.quantization)
                guard !variants.isEmpty else { return nil }
                return "\(backend): \(variants.joined(separator: "/"))"
            }
            lines.append(
                "\(size.padding(toLength: 16, withPad: " ", startingAt: 0)) (\(quants.joined(separator: " · ")))")
        }
        // Live non-Whisper families (#35/#50, spec model-grid "Full-family
        // catalog") — every bundled non-whisper backend renders its own rows.
        let liveFamilies = [
            ModelGrid.backendFluidParakeet, ModelGrid.backendFluidParaformer,
            ModelGrid.backendFluidSenseVoice,
        ]
        for backend in liveFamilies {
            for row in ModelGrid.rows(backend: backend, priorityCeiling: nil) {
                lines.append(
                    "\(row.size.padding(toLength: 16, withPad: " ", startingAt: 0)) "
                        + "(\(row.backend): \(row.quantization)\(row.verified ? "" : " · unverified"))")
            }
        }
        lines.append("")
        let mlxRegistered = engines.contains { $0.id == .mlxAudio }
        lines.append(
            mlxRegistered
                ? "mlx-audio catalog (external adapter registered — runnable; * = verified repo+pin):"
                : "mlx-audio reference catalog (backend not bundled; * = verified repo+pin):")
        for row in ModelGrid.rows(backend: ModelGrid.backendMLXAudio, priorityCeiling: nil)
            .sorted(by: { ($0.priority, $0.family) < ($1.priority, $1.family) })
        {
            let name = "\(row.family)/\(row.size)"
            lines.append(
                "  P\(row.priority) \(name.padding(toLength: 28, withPad: " ", startingAt: 0)) "
                    + "\(row.quantization)\(row.verified ? " *" : "")")
        }
        return lines.joined(separator: "\n")
    }
}
