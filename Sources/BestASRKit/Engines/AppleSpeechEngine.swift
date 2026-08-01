import AVFoundation
import Foundation
import Speech

/// The OS-native ASR backend (#121): Speech.framework's `SpeechAnalyzer` +
/// `SpeechTranscriber`, introduced in macOS 26. It is the only backend in the
/// pool with no dependency, no weight download, and no supply-chain pin — the
/// model ships with the operating system, so its version IS the OS version.
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

    /// Map a bestASR language tag onto one of Apple's supported locale
    /// identifiers. Pure and total over its inputs (the supported set is passed
    /// in, never queried here) so the mapping is testable on any OS and the
    /// runtime truth still comes from `SpeechTranscriber.supportedLocales`.
    ///
    /// Resolution order, most specific first:
    ///   1. an explicitly requested region that Apple supports (`zh-cn` → zh_CN)
    ///   2. the documented preference for the base language (`zh` → zh_TW)
    ///   3. the lexicographically smallest remaining candidate — deterministic,
    ///      so a future OS reordering its list cannot change a benchmark result
    ///
    /// A requested region Apple does NOT ship degrades within the same language
    /// (`pt-us` → pt_PT): the language is what decides whether output is usable
    /// at all, the region only shades it. A script subtag is not a region and
    /// falls through to step 2 (`zh-hant` → zh_TW); pass `zh-CN`/`zh-TW` to
    /// select a script explicitly.
    ///
    /// Throws — never falls back across languages. That fallback is precisely
    /// the failure this backend was measured producing.
    static func resolveLocaleIdentifier(language: String?, supported: [String]) throws -> String {
        guard let requested = LanguageResolver.resolve(language) else {
            throw TranscriptionError(backend: backendName, message: missingLanguageMessage)
        }
        let parts = requested.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard let base = parts.first.map(String.init), !base.isEmpty else {
            throw TranscriptionError(backend: backendName, message: missingLanguageMessage)
        }
        let requestedRegion = parts.count > 1 ? String(parts[1]) : nil

        let candidates = supported.filter { Self.baseSubtag(ofLocale: $0) == base }
        guard !candidates.isEmpty else {
            throw TranscriptionError(
                backend: backendName,
                message: "no Apple Speech locale supports language '\(requested)'. "
                    + "SpeechTranscriber advertises \(supported.count) locale(s) on this "
                    + "system; run a supported language instead — this backend will not "
                    + "substitute another language's model.")
        }
        if let requestedRegion,
            let exact = candidates.first(where: {
                Self.region(ofLocale: $0)?.lowercased() == requestedRegion
            }) {
            return exact
        }
        if let preferred = preferredRegions[base],
            let hit = candidates.first(where: {
                Self.region(ofLocale: $0)?.lowercased() == preferred.lowercased()
            }) {
            return hit
        }
        // `candidates` is non-empty, so `min` is total.
        return candidates.min()!
    }

    /// "zh" from "zh_TW" / "zh-TW", lowercased.
    private static func baseSubtag(ofLocale identifier: String) -> String {
        let lowered = identifier.lowercased()
        return lowered.split(whereSeparator: { $0 == "_" || $0 == "-" })
            .first.map(String.init) ?? lowered
    }

    /// "TW" from "zh_TW"; nil when the identifier carries no second subtag.
    private static func region(ofLocale identifier: String) -> String? {
        let parts = identifier.split(whereSeparator: { $0 == "_" || $0 == "-" })
        return parts.count > 1 ? String(parts[1]) : nil
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
    static func aggregateConfidence(_ perRun: [Double?]) -> Double? {
        guard !perRun.isEmpty else { return nil }
        var lowest = Double.infinity
        for value in perRun {
            guard let value else { return nil }
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

        try await installAssetIfNeeded(locale: locale, transcriber: transcriber)

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

        let results: [SpeechTranscriber.Result]
        do {
            // `results` is an AsyncSequence — the collector MUST be running
            // before audio is fed, or results are lost (see type doc, item 1).
            let collector = Task { () -> [SpeechTranscriber.Result] in
                var collected: [SpeechTranscriber.Result] = []
                for try await result in transcriber.results { collected.append(result) }
                return collected
            }
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
            segments: segments(from: results),
            language: options.language,
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
        let installed = await SpeechTranscriber.installedLocales
        guard !installed.contains(where: { $0.identifier == locale.identifier }) else { return }
        do {
            // nil = the system reports nothing left to install for these
            // modules; proceed rather than inventing a failure.
            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber])
            else { return }
            try await request.downloadAndInstall()
        } catch {
            throw TranscriptionError(
                backend: backendName,
                message: "failed to install the on-device speech asset for locale "
                    + "'\(locale.identifier)': \(error.localizedDescription)",
                underlying: error)
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
    static func segments(from results: [SpeechTranscriber.Result])
        -> [RawTranscription.RawSegment]
    {
        results.compactMap { result in
            let text = String(result.text.characters)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            // CMTime seconds are NaN/±inf for invalid or indefinite times —
            // never let one into a cue's timing (#53 seam-defense discipline).
            let start = result.range.start.seconds
            let span = result.range.duration.seconds
            guard start.isFinite, start >= 0, span.isFinite, span >= 0 else { return nil }
            return .init(
                start: start,
                end: start + span,
                text: text,
                confidence: aggregateConfidence(runConfidences(result.text)),
                // Whisper-specific hallucination signals; this backend
                // computes neither, and nil never trips a threshold (#100).
                noSpeechProb: nil,
                compressionRatio: nil)
        }
    }
}
