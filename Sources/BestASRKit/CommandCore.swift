import Foundation

/// The outcome of a `transcribe` invocation, for the CLI to report.
public struct TranscribeOutcome: Sendable {
    public let outputPath: String
    public let format: String
    public let explanation: String
    /// Router warnings, carried SEPARATELY from `explanation` (#136).
    ///
    /// They used to exist only folded into that prose block, which the CLI
    /// prints solely under `--explain` — so a user who asked for one backend
    /// and silently received another's output saw nothing but "Wrote txt
    /// transcript to …". `reason` is explanatory detail and can stay behind the
    /// flag; a warning is what the reader needs in order to trust the file that
    /// was just written, and cannot.
    public let warnings: [String]

    public init(
        outputPath: String, format: String, explanation: String, warnings: [String] = []
    ) {
        self.outputPath = outputPath
        self.format = format
        self.explanation = explanation
        self.warnings = warnings
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
    /// #105: detects the audio's language when `--language auto` resolved to
    /// nil, so routing never falls back to language-agnostic ranking silently.
    let languageDetector: any AudioLanguageDetecting

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
        dynamicHost: @escaping @Sendable () -> DynamicHostState = { .probe() },
        languageDetector: any AudioLanguageDetecting = WhisperKitLanguageDetector()
    ) {
        self.engines = engines
        self.detect = detect
        self.store = store
        self.diarizer = diarizer
        self.enroller = enroller
        self.dynamicHost = dynamicHost
        self.probe = probe
        self.languageDetector = languageDetector
    }

    /// Test seam for `live()` (#136).
    ///
    /// The `transcribe` command's own wiring — that it reports at all, on the
    /// default path, to the right descriptor — was asserted for four rounds by
    /// reading `BestASRCommand.swift` as text, because `live()` hard-wires six
    /// engines plus the external registry and `NSHomeDirectory()` ignores
    /// `$HOME` on Darwin, so there was no way to run the command under test.
    /// Each round the text pin was shown through on an axis it had not been
    /// told about: guard spelling, then stream labels, then the payload
    /// argument, then whether `--explain` still existed. An executed test needs
    /// to be told none of them.
    ///
    /// `@TaskLocal` rather than a settable global: the binding is scoped to the
    /// task that sets it, so parallel tests cannot see each other's injection
    /// and nothing has to be restored. Production never sets it, so `live()`
    /// keeps its exact previous behaviour — this is the only line that reads it.
    @TaskLocal public static var injected: CommandCore?

    /// The production wiring: real engines, real detection, real store.
    public static func live() -> CommandCore {
        if let injected { return injected }
        return {
        // Registered external adapters (#51, spec external-engine-protocol)
        // join the pool next to the bundled engines; with no registry config
        // this is exactly the bundled set.
        var engines: [any Engine] = [
            WhisperKitEngine(), WhisperCppEngine(), ParakeetEngine(),
            ChineseFamilyEngine.paraformer(), ChineseFamilyEngine.sensevoice(),
            // #121: registered unconditionally. The struct is constructible at
            // the package's macOS 14 deployment target; its isAvailable() is
            // the pure macOS-26 gate, so an older host simply reports it as
            // not installed instead of failing to build or link.
            AppleSpeechEngine(),
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
        /// `nil` when the selected backend takes no conditioning text, so no
        /// prompt was rendered. Distinct from a bundle whose prompt happens to
        /// be empty: nil means the question did not apply.
        let rendered: PromptRenderer.Rendered?
    }

    /// Resolve + load + render. Returns nil when nothing resolves or the
    /// directory holds neither values nor ignorable files — zero impact.
    /// A directory that only holds unsupported files still returns a bundle
    /// (prompt nil) so the ignore list is disclosed loudly, never silently.
    ///
    /// - Parameter capability: the selected backend's declaration. When it
    ///   reports no usable budget, rendering is **skipped entirely** rather than
    ///   performed and discarded (design D3): the truncation arithmetic would be
    ///   real work producing figures that describe nothing, and reporting an
    ///   injected count for a backend that consumes none is the misstatement
    ///   this whole change exists to remove.
    ///
    ///   `nil` means "no single backend applies" — the benchmark's ±context
    ///   delta mode measures many candidates in one run — and keeps the
    ///   previous global default.
    func loadContext(flag: String?, capability: PromptCapability? = nil) throws -> ContextBundle? {
        guard let loaded = try ContextLoader.load(flag: flag) else { return nil }
        if loaded.isEmpty && loaded.ignoredFiles.isEmpty { return nil }
        if let capability, !capability.supportsPrompt {
            return ContextBundle(loaded: loaded, rendered: nil)
        }
        let budget = capability?.effectiveBudget ?? PromptRenderer.defaultTokenBudget
        return ContextBundle(
            loaded: loaded, rendered: PromptRenderer.render(loaded, tokenBudget: budget))
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

    /// Wording used wherever a backend cannot consume conditioning text. Naming
    /// the *predicate* once keeps the reason line, the selection warning and the
    /// explain block from drifting apart while each caller supplies its own
    /// subject — folding the subject in here produced "selected backend this
    /// backend does not support …" (#164 verify).
    static let contextUnsupportedNote =
        "does not support context biasing — the context will not affect this transcription"

    /// The declaration of the engine registered for `backend`, or nil when none
    /// is registered (the caller then keeps the previous global default).
    func promptCapability(for backend: BackendID) -> PromptCapability? {
        engines.first(where: { $0.id == backend })?.promptCapability
    }

    /// Which capability the benchmark should render its single context prompt
    /// against (#164 verify). The benchmark has no one "selected" engine, which
    /// is why `loadContext` takes the capability as an optional — but the
    /// prompt now only reaches candidates that declare support, so:
    ///
    /// - candidates agreeing on one budget → that budget, so this call site
    ///   obeys "the budget comes from the engine" like the other two;
    /// - nothing in the grid can take a prompt → `.unsupported`, so no prompt
    ///   is rendered for a pass that cannot happen;
    /// - candidates disagreeing → nil (keep the global default): one prompt
    ///   cannot honour two budgets, and the smaller backend's own clamp is
    ///   the remaining backstop.
    ///
    /// Note the deliberate asymmetry with `promptCapability(for:)`, whose nil
    /// means "unknown — no engine registered" and tells its caller to keep the
    /// global default. Here an unregistered candidate contributes nothing and
    /// a grid of *only* unregistered candidates therefore yields `.unsupported`
    /// rather than nil. That is intentional: this function's job is "can the
    /// with-context pass happen at all", and a candidate with no engine cannot
    /// run any pass — `BenchmarkRunner` will not measure it either. The case is
    /// unreachable from `benchmark()` regardless, because `enumerateCandidates`
    /// derives candidates from the same `engines` array, but the reasoning is
    /// recorded here because two reviewers read the old wording in opposite
    /// ways (#164 verify round 2).
    func benchmarkPromptCapability(for candidates: [BenchmarkCandidate]) -> PromptCapability? {
        var budgets = Set<Int>()
        for candidate in candidates {
            guard let capability = promptCapability(for: candidate.backend) else { continue }
            if let budget = capability.effectiveBudget { budgets.insert(budget) }
        }
        if budgets.isEmpty { return .unsupported }
        guard budgets.count == 1, let budget = budgets.first else { return nil }
        return .supported(maxTokens: budget)
    }

    /// Selection-time warning (design D5). Returns nil when there is nothing to
    /// warn about — including when no engine is registered for the choice, since
    /// inventing a warning from an unknown is worse than staying quiet.
    static func contextCapabilityWarning(_ capability: PromptCapability?) -> String? {
        guard let capability, !capability.supportsPrompt else { return nil }
        return "the selected backend \(Self.contextUnsupportedNote)"
    }

    static func contextReasonLine(_ bundle: ContextBundle) -> String {
        guard let rendered = bundle.rendered else {
            return "context: \(bundle.loaded.directory) — this backend \(Self.contextUnsupportedNote)"
        }
        if rendered.injected.isEmpty {
            return "context: \(bundle.loaded.directory) — 0 values injected; "
                + "\(bundle.loaded.ignoredFiles.count) file(s) ignored (run the context-ingest skill)"
        }
        return "context: \(bundle.loaded.directory) — \(rendered.injected.count) value(s) injected"
    }

    /// Explain-mode disclosure (design D9): resolved dir, injected values,
    /// truncated items, ignored files with ingestion guidance.
    ///
    /// When the backend takes no prompt there is no injected count and no
    /// truncation list to report — printing `injected (N)` there was the
    /// original complaint: it reads as "this worked", and a user acts on it by
    /// trimming their term list, which changes nothing (spec `Explain discloses
    /// context usage`).
    static func contextExplanation(_ bundle: ContextBundle) -> [String] {
        var lines = ["Context: \(bundle.loaded.directory)"]
        guard let rendered = bundle.rendered else {
            lines.append("  this backend \(Self.contextUnsupportedNote)")
            for file in bundle.loaded.ignoredFiles {
                lines.append("  ignored: \(file) — \(LoadedContext.ingestGuidance)")
            }
            return lines
        }
        lines.append(
            "  injected (\(rendered.injected.count)): "
                + (rendered.injected.isEmpty
                    ? "(none)" : rendered.injected.joined(separator: ", ")))
        if !rendered.truncated.isEmpty {
            lines.append(
                "  truncated (\(rendered.truncated.count)): "
                    + rendered.truncated.joined(separator: ", "))
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

    /// #105: `--language auto` used to rank language-agnostically (English-
    /// biased in practice — parakeet's flattering en record won a mixed pool
    /// for zh audio). With no resolved language, detect it from the audio
    /// first; on failure fall back to nil ranking with an explicit warning
    /// instead of failing the command.
    static let detectionUnavailableWarning =
        "language auto-detection unavailable; ranking is language-agnostic and "
        + "may recommend a backend that does not support the audio's language"

    func resolveAutoLanguage(
        audioPath: String, resolved: String?
    ) async -> (language: String?, reasons: [String], warnings: [String]) {
        if let resolved { return (resolved, [], []) }
        do {
            let detected = try await languageDetector.detectLanguage(audioPath: audioPath)
            guard let base = LanguageResolver.resolve(detected) else {
                return (nil, [], [Self.detectionUnavailableWarning])
            }
            return (
                base,
                ["detected language '\(base)' from the first 30s of audio (--language auto)"],
                []
            )
        } catch {
            return (nil, [], [Self.detectionUnavailableWarning])
        }
    }

    public func recommendJSON(audioPath: String, selection: SelectionRequest) async throws -> String {
        let audio = try AudioProber.probe(
            path: audioPath, requestedLanguage: selection.requestedLanguage)
        let lang = await resolveAutoLanguage(audioPath: audio.path, resolved: audio.language)
        var rec = try await resolveRecommendation(selection: selection, language: lang.language)
        rec = rec.merging(reasons: lang.reasons, warnings: lang.warnings)
        let selectedCapability = promptCapability(for: rec.backend)
        if let bundle = try loadContext(
            flag: selection.contextDir, capability: selectedCapability)
        {
            // D5: surface the trade-off, do not decide it. The backend stays
            // selected — whether a lower measured error rate is worth losing
            // context biasing has not been measured, and quietly re-ranking on
            // an unmeasured belief would be the same overreach in the other
            // direction.
            var warnings = rec.warnings
            if let note = Self.contextCapabilityWarning(selectedCapability) {
                warnings.append(note)
            }
            rec = ASRRecommendation(
                backend: rec.backend, model: rec.model, quantization: rec.quantization,
                profile: rec.profile, language: rec.language, dataSource: rec.dataSource,
                measured: rec.measured,
                reason: rec.reason + [Self.contextReasonLine(bundle)],
                warnings: warnings
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
        let lang = await resolveAutoLanguage(audioPath: audio.path, resolved: audio.language)
        let resolved = (try await resolveRecommendation(
            selection: selection, language: lang.language))
            .merging(reasons: lang.reasons, warnings: lang.warnings)
        guard let engine = engines.first(where: { $0.id == resolved.backend }) else {
            throw BestASRError.runtime(
                "no engine registered for backend \(resolved.backend.rawValue)")
        }

        // The engine is resolved above, so the render budget can come from the
        // backend that will actually receive the prompt (design D3).
        let context = try loadContext(
            flag: selection.contextDir, capability: engine.promptCapability)

        // The D5 warning belongs to *selection*, not to one subcommand — this
        // command selects a backend too, so it carries the same warning
        // `recommend` does when the choice cannot use the resolved context
        // (#164 verify). Merged after loadContext so it fires only when a
        // context directory actually resolved.
        let rec = context == nil
            ? resolved
            : resolved.merging(
                reasons: [],
                warnings: [Self.contextCapabilityWarning(engine.promptCapability)].compactMap { $0 })
        let transcript = try await engine.transcribe(
            audioPath: audio.path,
            options: TranscribeOptions(
                model: rec.model, quantization: rec.quantization,
                language: lang.language, prompt: context?.rendered?.prompt,
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
            explanation: explanation.joined(separator: "\n"),
            warnings: rec.warnings
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
        decodeDeterministic: Bool = false,
        runKind: String? = nil
    ) async throws -> String {
        let profile = try Self.parseProfile(profileName)

        // Reference problems are usage errors raised BEFORE any transcription.
        // .srt parses as cues; anything else (the canonical corpus ships plain
        // .txt transcripts — `corpus pull`'s "Next: bestasr benchmark" promise)
        // reads verbatim as the reference text.
        let referenceText: String
        if referencePath.lowercased().hasSuffix(".srt") {
            let cues = try SRTParser.parse(fileAt: referencePath)
            referenceText = SRTParser.referenceText(from: cues)
        } else {
            let raw = try String(
                contentsOfFile: (referencePath as NSString).expandingTildeInPath,
                encoding: .utf8)
            referenceText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !referenceText.isEmpty else {
                throw BestASRError.usage("reference file is empty: \(referencePath)")
            }
        }

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

        // ±context delta mode (spec benchmark): context is loaded via the same
        // three-layer resolution; the runner measures a second with-context
        // pass per candidate while the cache stays baseline-only. The render
        // budget comes from the candidates that can actually consume it, and
        // the runner skips the pass for those that cannot (#164 verify).
        let contextBundle = try loadContext(
            flag: contextDir,
            capability: benchmarkPromptCapability(for: enumeration.candidates))
        let outcome = await runner.run(
            candidates: enumeration.candidates,
            notes: enumeration.notes
                + (contextBundle.map { bundle in
                    [
                        bundle.rendered.map {
                            "context: \(bundle.loaded.directory) — "
                                + "\($0.injected.count) value(s) in the with-context pass"
                        }
                            ?? "context: \(bundle.loaded.directory) — "
                            + "no candidate supports a prompt; no with-context pass"
                    ]
                } ?? []),
            audio: audio,
            referenceText: referenceText,
            metricKind: metricKind,
            language: resolvedLanguage ?? "auto",
            contextPrompt: contextBundle?.rendered?.prompt,
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
                hfRevision: seededRow?.hfRevision,
                runKind: runKind,
                // The honest gate lives in DecodeDeterminism.forBackend (#120
                // item 1) so the "never lie" invariant is unit-testable without
                // running a real backend. Non-optional by construction: a live
                // measurement always knows something; nil is for legacy rows.
                decodeDeterministic: .forBackend(
                    record.backend, flagRequested: decodeDeterministic)))
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
            // #121: the OS-native backend is bundled too — a catalog row the
            // catalog never prints is undiscoverable.
            ModelGrid.backendAppleSpeech,
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
