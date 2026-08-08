import AVFoundation
import Foundation
import Speech

/// The OS-native ASR backend (#121): Speech.framework's `SpeechAnalyzer` +
/// `SpeechTranscriber`, introduced in macOS 26. It is the only backend in the
/// pool with no third-party dependency and no HuggingFace weight pin — the
/// recognizer ships with the operating system, so its version IS the OS version.
///
/// That is NOT the same as "downloads nothing": a locale whose asset is absent
/// is fetched from Apple on first use, and this project measured exactly that
/// (`ja_JP` was missing on the development machine and had to be installed).
/// The supply-chain claim is about provenance — Apple rather than a model hub —
/// not about network traffic.
///
/// API mapping (live-probed on macOS 27 / Xcode 26.6 → BestASRKit):
///
/// | Speech.framework                                     | here                        |
/// |------------------------------------------------------|-----------------------------|
/// | `SpeechTranscriber(locale:…:attributeOptions:)`       | per-call, keyed by language |
/// | `SpeechAnalyzer(modules:)` + `analyzeSequence(from:)` | `transcribeRaw`             |
/// | `SpeechTranscriber.Result.range` (`CMTimeRange`)      | `RawSegment.start`/`.end`   |
/// | `Result.text` (`AttributedString`)                    | `RawSegment.text`           |
/// | per-run `ConfidenceAttribute`                         | `RawSegment.confidence` (min)|
/// | `AssetInventory.assetInstallationRequest(supporting:)`| `transcribeRaw` preflight   |
///
/// Three things about this framework are load-bearing and were established by
/// live probing rather than from the headers:
///
/// 1. **Consume `results` BEFORE feeding audio.** `transcriber.results` is an
///    `AsyncSequence`; starting the collector after `analyzeSequence` loses
///    results. The collector Task below is started first, deliberately.
/// 2. **The locale asset must be installed.** With the asset missing, Apple
///    throws `SFSpeechErrorDomain Code=3 "Audio format is not supported"` — a
///    MISLEADING message. It was proved not to be a format problem: three
///    corpora byte-identical in format (1ch/16 kHz/Int16) behaved differently,
///    and the same ja file transcribed fine under `en_US`. After installing the
///    ja asset the same file+locale worked immediately. **Never diagnose asset
///    availability from the error text — check `installedLocales`.**
/// 3. **There is no determinism knob.** The whole `Speech.swiftinterface` has
///    zero hits for temperature/greedy/beam/sampling/seed, so this backend
///    ignores `options.deterministicDecode`. `CommandCore`'s persistence gate
///    already records `decode_deterministic` only for the whisper-family
///    backends that actually consume it, so nothing here has to lie.
///
/// Availability is a pure OS-version gate: the struct itself carries no
/// `@available`, so `CommandCore.live()` can hold it unconditionally at the
/// package's macOS 14 deployment target, and every macOS-26-only call lives in
/// an `@available` helper below. `isAvailable()` never touches the asset
/// inventory — availability detection is specified as graceful AND cheap, and
/// an asset download takes tens of seconds.
public struct AppleSpeechEngine: Engine {
    public let id: BackendID = .appleSpeech

    /// `SpeechAnalyzer` exposes no conditioning-text parameter. (It does have a
    /// separate contextual-strings facility; that is a different mechanism and
    /// is not wired here — declaring support would misdescribe what happens.)
    public let promptCapability: PromptCapability = .unsupported

    public init() {}

    // MARK: - Diagnostics

    static let backendName = BackendID.appleSpeech.rawValue

    /// Thrown when transcription is requested below macOS 26. Held as a
    /// constant so the branch this machine cannot execute is still assertable.
    static let unsupportedOSMessage =
        "requires macOS 26 or later — SpeechAnalyzer / SpeechTranscriber "
        + "(Speech.framework) do not exist on this system. Run `bestasr "
        + "list-backends` to see which backends are usable here."

    /// The `--language` requirement, stated once. SpeechTranscriber selects a
    /// model by locale and has no autodetect mode, so an unresolved language
    /// cannot be papered over: guessing English produced measured garbage on
    /// Japanese audio (#121 probe), and a benchmark harness must not let a
    /// silent guess enter its evidence base.
    static let missingLanguageMessage =
        "requires an explicit transcription language: SpeechTranscriber selects "
        + "its model by locale and has no auto-detect mode, so a guessed locale "
        + "silently degrades output (a ja file decoded under en_US yields "
        + "garbage). Re-run with an explicit --language (e.g. en, ja, zh)."

    // MARK: - Locale resolution

    /// Which region to pick for a base language that Apple ships in several.
    /// Policy, not fact — hence a hand-maintained table with the reasoning:
    ///
    /// - `en` → US and `ja` → JP and `zh` → TW are bestASR's benchmark triple.
    ///   zh is the load-bearing one: the zh corpora are Common Voice zh-TW
    ///   (`RegressionBaselineTests` requires corpus names to start `cv-zhtw-`),
    ///   and the lexicographic fallback would otherwise pick zh_CN.
    /// - The rest resolve to the language's own national variant (de_DE, fr_FR,
    ///   it_IT, pt_PT, es_ES) rather than a secondary region (de_AT, fr_BE, …).
    ///
    /// Base languages Apple ships in exactly ONE region need no entry — the
    /// resolver finds the single candidate on its own, so this table stays as
    /// small as the genuine ambiguity. `AppleSpeechGridTests` locks every entry
    /// against the probed supported set so a typo cannot demote silently.
    static let preferredRegions: [String: String] = [
        "en": "US", "ja": "JP", "zh": "TW",
        "de": "DE", "es": "ES", "fr": "FR", "it": "IT", "pt": "PT",
    ]

    /// Which region carries a given script, for tags that name a script rather
    /// than a country. Only entries whose mapping is unambiguous belong here.
    ///
    /// This table exists because a subtag's POSITION does not identify it: in
    /// `zh-Hans` the second subtag is a script, in `zh-CN` it is a region.
    /// Reading position-2 as "the region" made `zh-Hans` miss every candidate
    /// and fall through to the `zh` preference — so a user who explicitly asked
    /// for **Simplified** silently received the **Traditional** model. Verified
    /// by probe before the fix: `zh-Hans` → `zh_TW`.
    static let scriptRegions: [String: String] = ["hans": "CN", "hant": "TW"]

    /// A parsed language tag. `script` and `region` are distinguished by SHAPE
    /// (BCP-47: script is 4 alpha, region is 2 alpha or 3 digits), never by
    /// position, so `zh-Hans`, `zh-CN` and `zh-Hans-CN` each parse correctly.
    struct ParsedTag {
        var base: String
        var script: String?
        var region: String?
    }

    /// Shape-directed subtag parse. Lowercased throughout — `LanguageResolver`
    /// already lowercases the request, and locale identifiers are lowercased
    /// on the way in, so comparisons never depend on the caller's casing.
    static func parseTag(_ tag: String) -> ParsedTag? {
        let parts = tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard let first = parts.first, first.count >= 2, first.allSatisfy(\.isLetter) else {
            return nil
        }
        var parsed = ParsedTag(base: String(first), script: nil, region: nil)
        for part in parts.dropFirst() {
            if part.count == 4, part.allSatisfy(\.isLetter) {
                parsed.script = parsed.script ?? String(part)
            } else if (part.count == 2 && part.allSatisfy(\.isLetter))
                || (part.count == 3 && part.allSatisfy(\.isNumber)) {
                parsed.region = parsed.region ?? String(part)
            }
            // Variants/extensions are not selectors for this API — ignored.
        }
        return parsed
    }

    /// Apple's `zh_TW` in the hyphenated BCP-47 form the rest of this project
    /// parses. See the call site in `transcribe` for why this is load-bearing.
    static func bcp47(_ localeIdentifier: String) -> String {
        localeIdentifier.replacingOccurrences(of: "_", with: "-")
    }

    /// Map a bestASR language tag onto one of Apple's supported locale
    /// identifiers. Pure and total over its inputs (the supported set is passed
    /// in, never queried here) so the mapping is testable on any OS and the
    /// runtime truth still comes from `SpeechTranscriber.supportedLocales`.
    ///
    /// Resolution order, most specific first:
    ///   1. an explicitly requested REGION that Apple supports (`zh-CN` → zh_CN)
    ///   2. the region implied by an explicitly requested SCRIPT
    ///      (`zh-Hans` → CN → zh_CN)
    ///   3. the documented preference for the base language (`zh` → zh_TW)
    ///   4. the lexicographically smallest remaining candidate — deterministic,
    ///      so a future OS reordering its list cannot change a benchmark result
    ///
    /// Region outranks script because a region is the more specific claim and
    /// the combination is legitimate (`zh-Hans-TW` = Simplified as written in
    /// Taiwan; Apple ships no such locale, and the explicit region is the
    /// better-evidenced half of the request).
    ///
    /// A requested region Apple does NOT ship degrades within the same language
    /// (`pt-BR` → pt_PT when only pt_PT exists): the language decides whether
    /// output is usable at all, the region only shades it. The caller is told
    /// which locale actually ran — see `transcribe`, which records the RESOLVED
    /// identifier rather than the requested tag.
    ///
    /// Throws — never falls back across languages. That fallback is precisely
    /// the failure this backend was measured producing.
    static func resolveLocaleIdentifier(language: String?, supported: [String]) throws -> String {
        guard let requested = LanguageResolver.resolve(language),
            let tag = parseTag(requested)
        else {
            throw TranscriptionError(backend: backendName, message: missingLanguageMessage)
        }

        let candidates = supported.filter { Self.parseTag($0)?.base == tag.base }
        guard !candidates.isEmpty else {
            throw TranscriptionError(
                backend: backendName,
                message: "no Apple Speech locale supports language '\(requested)'. "
                    + "SpeechTranscriber advertises \(supported.count) locale(s) on this "
                    + "system; run a supported language instead — this backend will not "
                    + "substitute another language's model.")
        }
        func match(region: String?) -> String? {
            guard let region = region?.lowercased() else { return nil }
            return candidates.first { Self.parseTag($0)?.region == region }
        }
        if let exact = match(region: tag.region) { return exact }
        if let script = tag.script, let hit = match(region: scriptRegions[script]) { return hit }
        if let hit = match(region: preferredRegions[tag.base]) { return hit }
        // `candidates` is non-empty, so `min` is total.
        return candidates.min()!
    }

    // MARK: - Confidence

    /// One confidence per segment, derived from Apple's PER-RUN values.
    ///
    /// `SpeechTranscriber` attaches `transcriptionConfidence` to runs inside a
    /// result's `AttributedString`, while `RawSegment.confidence` is a single
    /// number per segment — so this value is DERIVED, not reported, and the
    /// aggregation is a choice worth stating: **the minimum over the runs.**
    ///
    /// Why min rather than a mean:
    ///   - It cannot overstate a cue. A mean lets a confident run mask a weak
    ///     one inside the SAME cue, and the cue is the unit a reader reads and
    ///     the hallucination filter drops.
    ///   - bestASR's only consumer of the field is a degradation detector
    ///     (`HallucinationFilter.full`), and a lower bound is the right shape
    ///     for a detector.
    ///   - It needs no weighting policy. A weighted mean would force a choice
    ///     between character count, run count, or audio duration per run —
    ///     Apple attaches confidence to runs, not to time — and any of those
    ///     would layer an unmeasured guess on top of a derived number.
    ///
    /// A run missing the attribute makes the whole segment nil: `confidence` is
    /// Optional precisely so "unknown" is representable, and an invented number
    /// would be worse than an absent one.
    ///
    /// Note the field is backend-defined across this project: WhisperKit stores
    /// `avgLogprob` there, FluidAudio Parakeet stores a 0…1 confidence. This
    /// backend follows Parakeet. `HallucinationFilter`'s joint silence rule
    /// cannot misfire on the difference — it also requires `noSpeechProb`,
    /// which is Whisper-specific and nil here.
    /// The value is a MINIMUM OBSERVED RUN CONFIDENCE, not a calibrated
    /// per-cue probability: more runs means more chances to hit a low one, so
    /// long cues score systematically lower. Do not threshold it across
    /// backends without re-establishing what it means there.
    static func aggregateConfidence(_ perRun: [Double?]) -> Double? {
        guard !perRun.isEmpty else { return nil }
        var lowest = Double.infinity
        for value in perRun {
            // A missing attribute makes the whole segment nil — the field is
            // Optional precisely so "unknown" is representable.
            guard let value else { return nil }
            // A non-finite or out-of-range value is not a low confidence, it
            // is a broken one. Reporting NaN as a number would let it sort and
            // compare nonsensically downstream; nil says "unknown", which is
            // the truth.
            guard value.isFinite, value >= 0, value <= 1 else { return nil }
            lowest = Swift.min(lowest, value)
        }
        return lowest
    }

    /// Per-run `transcriptionConfidence` values, in run order; nil for a run
    /// that carries no such attribute.
    @available(macOS 26.0, *)
    static func runConfidences(_ text: AttributedString) -> [Double?] {
        text.runs.map { run in
            run.attributes[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self]
        }
    }

    // MARK: - Engine

    public func isAvailable() async -> Bool {
        // Pure version gate — no asset inventory query, no download. See the
        // type doc: `list-backends` calls this for every backend.
        if #available(macOS 26.0, *) {
            return true
        } else {
            return false
        }
    }

    public func transcribeRaw(
        audioPath: String, options: TranscribeOptions
    ) async throws -> RawTranscription {
        guard #available(macOS 26.0, *) else {
            throw TranscriptionError(backend: id.rawValue, message: Self.unsupportedOSMessage)
        }
        return try await Self.transcribe(audioPath: audioPath, options: options)
    }

    // MARK: - macOS 26+ implementation

    @available(macOS 26.0, *)
    private static func transcribe(
        audioPath: String, options: TranscribeOptions
    ) async throws -> RawTranscription {
        let supported = await SpeechTranscriber.supportedLocales.map(\.identifier)
        let identifier = try resolveLocaleIdentifier(
            language: options.language, supported: supported)
        let locale = Locale(identifier: identifier)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            // Both attributes are required: audioTimeRange for cue times,
            // transcriptionConfidence for the per-run confidence the segment
            // value is derived from. Omitting either silently drops that field.
            attributeOptions: [.audioTimeRange, .transcriptionConfidence])

        // Open and validate the audio BEFORE any asset install. Installing
        // first meant `transcribe --language ja /nonexistent.wav` downloaded a
        // multi-hundred-MB locale asset and only then reported the missing
        // file — an expensive, networked failure for a cheap, local error.
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: URL(fileURLWithPath: audioPath))
        } catch {
            throw TranscriptionError(
                backend: backendName,
                message: "\(audioPath): \(error.localizedDescription)",
                underlying: error)
        }
        // The engine seam already normalized to 16 kHz mono (#36); this is the
        // true wall-clock length of what the analyzer will read.
        let duration = file.length > 0
            ? Double(file.length) / file.processingFormat.sampleRate : nil

        try await installAssetIfNeeded(locale: locale, transcriber: transcriber)

        let results: [SpeechTranscriber.Result]
        do {
            // `results` is an AsyncSequence — the collector MUST be running
            // before audio is fed, or results are lost (see type doc, item 1).
            let collector = Task { () -> [SpeechTranscriber.Result] in
                var collected: [SpeechTranscriber.Result] = []
                for try await result in transcriber.results { collected.append(result) }
                return collected
            }
            // The collector is UNSTRUCTURED, so it does not inherit
            // cancellation and is not awaited on the throwing paths below. If
            // the analyzer fails, an un-cancelled collector keeps iterating a
            // sequence that may never terminate, pinning the transcriber and
            // its buffers for the life of the process — across a benchmark
            // sweep that accumulates. `defer` covers every exit, including the
            // success path (where cancelling an already-finished Task is a
            // no-op) and cancellation of our own parent task.
            defer { collector.cancel() }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            results = try await collector.value
        } catch {
            throw TranscriptionError(
                backend: backendName,
                message: "\(audioPath) (locale \(identifier)): \(error.localizedDescription)",
                underlying: error)
        }

        return RawTranscription(
            segments: try segments(from: results),
            // The RESOLVED locale, not the requested tag. Recording the request
            // would attribute a measurement to a locale that never ran: ask for
            // `pt-BR` on a system shipping only `pt_PT` and the row would claim
            // pt-BR accuracy for a pt-PT model. Provenance must name what
            // executed (design D2).
            //
            // HYPHENATED, because Apple's identifiers are underscored and every
            // language predicate in this project routes through
            // `LanguageResolver.baseSubtag`, which splits on "-" ONLY. Emitting
            // `zh_TW` verbatim would make `baseSubtag` return "zh_tw", so
            // `isChinese` turns false and the D7 Traditional/Simplified fold
            // silently stops applying to this backend's zh scoring (#34).
            language: Self.bcp47(identifier),
            duration: duration)
    }

    /// Asset preflight. Lives here and NOT in `isAvailable()` because a
    /// download takes tens of seconds while availability must stay cheap.
    ///
    /// The check is `installedLocales`, never the error text: a missing asset
    /// surfaces as `SFSpeechErrorDomain Code=3 "Audio format is not supported"`,
    /// which sends the reader hunting a format bug that does not exist.
    @available(macOS 26.0, *)
    private static func installAssetIfNeeded(
        locale: Locale, transcriber: SpeechTranscriber
    ) async throws {
        func isInstalled() async -> Bool {
            // Compare canonically: an inventory that reports `zh-TW` while the
            // request holds `zh_TW` would otherwise look permanently missing
            // and re-trigger a download on every single call.
            let wanted = bcp47(locale.identifier).lowercased()
            return await SpeechTranscriber.installedLocales
                .contains { bcp47($0.identifier).lowercased() == wanted }
        }
        guard await !isInstalled() else { return }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw TranscriptionError(
                backend: backendName,
                message: "failed to install the on-device speech asset for locale "
                    + "'\(locale.identifier)': \(error.localizedDescription)",
                underlying: error)
        }
        // Re-check instead of trusting either branch. A nil request means "the
        // system has nothing to install", which CONTRADICTS the inventory that
        // just said the locale is missing; proceeding on that contradiction is
        // exactly how the misleading `Code=3 "Audio format is not supported"`
        // reaches the user — the error this preflight exists to prevent. A
        // completed download that still leaves the locale absent is equally
        // unusable. Both fail here, named for what they are.
        guard await isInstalled() else {
            throw TranscriptionError(
                backend: backendName,
                message: "the on-device speech asset for locale '\(locale.identifier)' is "
                    + "still not installed after the install attempt. Transcribing now would "
                    + "surface Apple's misleading \"Audio format is not supported\" error, "
                    + "which is really a missing-asset report. Check Settings ▸ General ▸ "
                    + "Language & Region, or free disk space, and retry.")
        }
    }

    /// One `SpeechTranscriber.Result` becomes one raw segment.
    ///
    /// Text is taken verbatim (`String(result.text.characters)`), including any
    /// leading space: `Engine.transcribe` joins segment texts with NO
    /// separator, so trimming here would glue words together across cues and
    /// inflate this backend's measured WER — the same contract WhisperKit's
    /// segments and #35's parakeet mapper follow.
    @available(macOS 26.0, *)
    static func segments(from results: [SpeechTranscriber.Result]) throws
        -> [RawTranscription.RawSegment]
    {
        try results.enumerated().compactMap { index, result in
            let text = String(result.text.characters)
            // Drop only a TRULY empty result. A whitespace-only one is kept:
            // `Engine.transcribe` joins segment texts with NO separator, so
            // discarding a segment that consists of the separator would glue
            // the neighbouring words together and change the hypothesis.
            guard !text.isEmpty else { return nil }
            // CMTime seconds are NaN/±inf for invalid or indefinite times —
            // never let one into a cue's timing (#53 seam-defense discipline).
            let start = result.range.start.seconds
            let span = result.range.duration.seconds
            let end = start + span
            // Recognized text with unusable timing FAILS THE RUN rather than
            // vanishing. Dropping it would edit the hypothesis invisibly: the
            // WER denominator is the reference word count and does not move,
            // so a dropped correct word adds a deletion while a dropped
            // garbage word removes an insertion — the measured number shifts
            // in an unsignposted direction. A benchmark tool must not do that
            // silently; an error the operator can see is the honest failure.
            // (`end` is checked separately: two finite addends can still
            // overflow to infinity.)
            guard start.isFinite, start >= 0, span.isFinite, span >= 0, end.isFinite else {
                throw TranscriptionError(
                    backend: backendName,
                    message: "result \(index) carries unusable timing "
                        + "(start \(start), duration \(span)) for non-empty text — refusing to "
                        + "drop recognized speech, which would silently bias the measured "
                        + "error rate")
            }
            return .init(
                start: start,
                end: end,
                text: text,
                confidence: aggregateConfidence(runConfidences(result.text)),
                // Whisper-specific hallucination signals; this backend
                // computes neither, and nil never trips a threshold (#100).
                noSpeechProb: nil,
                compressionRatio: nil)
        }
    }
}
