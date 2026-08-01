import Foundation
import Testing

@testable import BestASRKit

/// #121 — the OS-native Apple Speech backend (SpeechAnalyzer / SpeechTranscriber).
///
/// Every test here is HERMETIC: no real transcription, no asset download, no
/// network. The locale table below is the live-probed ground truth from this
/// machine (macOS 27, `SpeechTranscriber.supportedLocales`, probed 2026-08-01)
/// used as a FIXTURE — the resolver takes the supported set as a parameter
/// precisely so it can be tested without calling into the OS.
struct AppleSpeechLocaleResolutionTests {
    /// The 45 locales `SpeechTranscriber.supportedLocales` reported on macOS 27.
    static let supported: [String] = [
        "bn_IN", "de_AT", "de_CH", "de_DE", "en_AU", "en_CA", "en_GB", "en_IE",
        "en_IN", "en_NZ", "en_SG", "en_US", "en_ZA", "es_CL", "es_ES", "es_MX",
        "es_US", "fr_BE", "fr_CA", "fr_CH", "fr_FR", "gu_IN", "hi_IN", "it_CH",
        "it_IT", "ja_JP", "kn_IN", "ko_KR", "ks_IN", "mai_IN", "ml_IN", "mr_IN",
        "mul_IN", "ne_IN", "or_IN", "pa_IN", "pt_BR", "pt_PT", "ta_IN", "te_IN",
        "ur_IN", "yue_CN", "zh_CN", "zh_HK", "zh_TW",
    ]

    @Test func `bestASR's three benchmark languages map to their Apple locales`() throws {
        // The corpora this project measures against: en (LibriSpeech-class),
        // ja, and zh — the zh suite is Common Voice zh-TW (RegressionBaseline
        // asserts corpus names start `cv-zhtw-`), so bare "zh" MUST resolve to
        // Traditional zh_TW, not the lexicographically-first zh_CN.
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "en", supported: Self.supported) == "en_US")
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "ja", supported: Self.supported) == "ja_JP")
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "zh", supported: Self.supported) == "zh_TW")
    }

    @Test func `An explicit region is honored verbatim when Apple supports it`() throws {
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "zh-cn", supported: Self.supported) == "zh_CN")
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "en-gb", supported: Self.supported) == "en_GB")
        // Underscore form and case are both accepted (store rows and CLI input
        // disagree on style; the resolver must not).
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "PT_br", supported: Self.supported) == "pt_BR")
    }

    @Test func `A base language with exactly one region needs no preference entry`() throws {
        // ko/ja/hi… each have a single supported locale — the resolver must
        // find them without a hand-maintained table entry.
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "ko", supported: Self.supported) == "ko_KR")
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "hi", supported: Self.supported) == "hi_IN")
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "yue", supported: Self.supported) == "yue_CN")
    }

    @Test func `Ambiguous base languages resolve to the documented preference, deterministically`() throws {
        // de_AT sorts first; the preference table must win, or the choice
        // would silently depend on Apple's list ordering.
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "de", supported: Self.supported) == "de_DE")
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "fr", supported: Self.supported) == "fr_FR")
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "it", supported: Self.supported) == "it_IT")
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "pt", supported: Self.supported) == "pt_PT")
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "es", supported: Self.supported) == "es_ES")
    }

    @Test func `An unsupported region degrades within the same language, never across languages`() throws {
        // pt_US does not exist; falling back to pt_PT keeps the LANGUAGE right,
        // which is the only property that decides whether output is usable.
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "pt-us", supported: Self.supported) == "pt_PT")
        // A script subtag is not a region — documented fall-through to the
        // base preference (pass zh-CN / zh-TW to pick a script explicitly).
        #expect(
            try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "zh-hant", supported: Self.supported) == "zh_TW")
    }

    @Test func `An unsupported language throws and names the language — never a silent English fallback`() {
        // The failure mode this guards: a ja file decoded under en_US produced
        // measured garbage. Falling back to English is worse than failing.
        do {
            _ = try AppleSpeechEngine.resolveLocaleIdentifier(
                language: "sw", supported: Self.supported)
            Issue.record("expected an unsupported language to throw")
        } catch let error as TranscriptionError {
            #expect(error.backend == "apple-speech")
            #expect(error.message.contains("sw"))
            #expect(!error.message.contains("en_US"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func `A nil or auto language is refused with actionable guidance, not guessed`() {
        // SpeechTranscriber has no language-autodetect mode; picking one for
        // the user is exactly the silent-degradation bug above.
        for requested in [nil, "auto", "  "] as [String?] {
            do {
                _ = try AppleSpeechEngine.resolveLocaleIdentifier(
                    language: requested, supported: Self.supported)
                Issue.record("expected a nil/auto language to throw (\(requested ?? "nil"))")
            } catch let error as TranscriptionError {
                #expect(error.backend == "apple-speech")
                #expect(error.message.lowercased().contains("language"))
            } catch {
                Issue.record("unexpected error type: \(error)")
            }
        }
    }

    @Test func `An empty supported set throws rather than inventing a locale`() {
        #expect(throws: TranscriptionError.self) {
            _ = try AppleSpeechEngine.resolveLocaleIdentifier(language: "en", supported: [])
        }
    }

    @Test func `Every preferred region names a locale Apple actually supports`() {
        // Drift guard: the preference table is hand-maintained policy; a typo
        // ("en"/"UK") would silently demote to the lexicographic fallback.
        for (base, region) in AppleSpeechEngine.preferredRegions {
            #expect(
                Self.supported.contains("\(base)_\(region)"),
                "preferred locale \(base)_\(region) is not in the probed supported set")
        }
    }
}

struct AppleSpeechConfidenceTests {
    @Test func `Segment confidence is the minimum over the result's runs`() {
        // Apple reports confidence PER RUN; RawSegment carries one value per
        // segment, so the segment number is DERIVED. Min is the conservative
        // summary — a mean would let a confident run mask a bad one inside the
        // same cue, and the cue is the unit a reader (and the filter) acts on.
        #expect(AppleSpeechEngine.aggregateConfidence([0.985, 0.513]) == 0.513)
        #expect(AppleSpeechEngine.aggregateConfidence([0.4]) == 0.4)
    }

    @Test func `A run without the confidence attribute makes the whole segment nil`() {
        // An invented number is worse than an absent one — RawSegment.confidence
        // is Optional precisely so "unknown" is representable.
        #expect(AppleSpeechEngine.aggregateConfidence([0.9, nil]) == nil)
        #expect(AppleSpeechEngine.aggregateConfidence([nil]) == nil)
        #expect(AppleSpeechEngine.aggregateConfidence([]) == nil)
    }

    @available(macOS 26.0, *)
    @Test func `Per-run confidences are read off a real AttributedString`() throws {
        // Proves the attribute key path itself (not just the aggregation):
        // a hand-built AttributedString carrying the Speech confidence
        // attribute round-trips through the extractor. No ASR involved.
        var first = AttributedString("And")
        first[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] = 0.985
        var second = AttributedString(" Ask")
        second[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] = 0.513
        let combined = first + second
        #expect(AppleSpeechEngine.runConfidences(combined) == [0.985, 0.513])
        #expect(AppleSpeechEngine.aggregateConfidence(
            AppleSpeechEngine.runConfidences(combined)) == 0.513)

        // A run with no attribute reads as nil rather than a default.
        let bare = AttributedString("hello")
        #expect(AppleSpeechEngine.runConfidences(bare) == [nil])
    }
}

struct AppleSpeechAvailabilityTests {
    @Test func `Availability is exactly the macOS 26 gate`() async {
        let engine = AppleSpeechEngine()
        let available = await engine.isAvailable()
        // Both branches are expressed; this host runs whichever applies.
        if #available(macOS 26.0, *) {
            #expect(available == true)
        } else {
            #expect(available == false)
        }
    }

    @Test func `Availability probing is cheap — it must never download an asset`() async {
        // Asset installation takes tens of seconds; availability detection is
        // specified as graceful and cheap (spec asr-engine), and `bestasr
        // list-backends` calls it for every backend.
        let engine = AppleSpeechEngine()
        let start = Date()
        _ = await engine.isAvailable()
        #expect(Date().timeIntervalSince(start) < 5.0)
    }

    @Test func `The pre-macOS-26 refusal names the requirement and the framework`() {
        // The path this machine cannot execute, asserted through the message
        // constant the guard throws.
        let message = AppleSpeechEngine.unsupportedOSMessage
        #expect(message.contains("macOS 26"))
        #expect(message.contains("SpeechAnalyzer"))
    }

    @Test func `The engine is constructible on the package's macOS 14 deployment target`() {
        // No @available on the type: CommandCore.live() holds it unconditionally
        // and isAvailable() does the gating. If this ever needs @available, the
        // engines array stops compiling for the deployment target.
        let engine = AppleSpeechEngine()
        #expect(engine.id == .appleSpeech)
        #expect(engine.id.rawValue == "apple-speech")
    }
}

struct AppleSpeechGridTests {
    @Test func `The apple-speech row is present and well-formed`() throws {
        let rows = ModelGrid.rows(backend: ModelGrid.backendAppleSpeech, priorityCeiling: nil)
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.quantization == "default")
        // Ships with macOS — there is no HuggingFace artifact to pin, and the
        // grid invariant forbids a repo id on an unverified row.
        #expect(row.hfRepo == nil)
        #expect(row.hfRevision == nil)
        // Never benchmarked through `bestasr benchmark` on this project's
        // corpora — `verified` stays false until a measurement exists.
        #expect(row.verified == false)
        #expect(row.priority == 1)
        #expect(row.estMemoryGB > 0)
    }

    @Test func `The row enumerates in the default priority-1 sweep`() {
        let sweep = ModelGrid.rows(backend: ModelGrid.backendAppleSpeech)
        #expect(sweep.count == 1)
    }

    @Test func `The row is reachable through the normal grid lookup, both address forms`() throws {
        let bare = try #require(
            ModelGrid.row(backend: ModelGrid.backendAppleSpeech, modelAddress: "system"))
        let addressed = try #require(
            ModelGrid.row(
                backend: ModelGrid.backendAppleSpeech,
                modelAddress: "\(bare.family)/\(bare.size)"))
        #expect(bare.modelId == addressed.modelId)
        #expect(bare.modelId == "apple-speech|speechanalyzer|system|default")
    }

    @Test func `Declared languages are the probed locale set — never the multi sentinel`() throws {
        let row = try #require(
            ModelGrid.row(backend: ModelGrid.backendAppleSpeech, modelAddress: "system"))
        // "multi" is reserved for the 99+/1000+ class (ModelRow doc comment);
        // 45 locales over 25 base subtags is not that class, and #105 is the
        // standing lesson about mislabeling a bounded set as multilingual.
        #expect(!row.languages.contains("multi"))
        // The three languages this project benchmarks must all be declared, or
        // the router's declared-support gate would warn on every zh/ja run.
        #expect(row.languages.contains("en"))
        #expect(row.languages.contains("ja"))
        #expect(row.languages.contains("zh"))
        // Exactly the base subtags of the 45 probed locales.
        let probed = Set(
            AppleSpeechLocaleResolutionTests.supported.map {
                String($0.split(separator: "_")[0])
            })
        #expect(Set(row.languages) == probed)
        #expect(row.languages.count == 25)
    }

    @Test func `Every declared language resolves to a supported Apple locale`() throws {
        // Round-trip lock: the grid row and the engine's resolver cannot drift
        // apart — anything the row advertises must be transcribable.
        let row = try #require(
            ModelGrid.row(backend: ModelGrid.backendAppleSpeech, modelAddress: "system"))
        for language in row.languages {
            let identifier = try AppleSpeechEngine.resolveLocaleIdentifier(
                language: language,
                supported: AppleSpeechLocaleResolutionTests.supported)
            #expect(identifier.hasPrefix("\(language)_"))
        }
    }

    @Test func `The registry carries a memory estimate for the row`() throws {
        let row = try #require(
            ModelGrid.row(backend: ModelGrid.backendAppleSpeech, modelAddress: "system"))
        let requirements = try ModelRegistry.requirements(for: row.size)
        #expect(requirements.memoryGB == row.estMemoryGB)
    }
}
