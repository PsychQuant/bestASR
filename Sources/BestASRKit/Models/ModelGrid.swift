import Foundation

/// The model catalog (#14; spec model-grid). Code-owned: seeded into the
/// store's models table wholesale. The mlx-audio rows are a REFERENCE
/// CATALOG (#20): the backend is not bundled, the rows are retained for
/// lookup (families, verified HF repos with pinned revisions) and potential
/// future reinstatement — they never enumerate as benchmark candidates.
/// Priority on reference rows is the historical first-run/representative/
/// deferred selection. `verified` marks rows whose HF repo id was checked
/// against the hub (probed 2026-07-02).
public enum ModelGrid {
    public static let backendWhisperKit = "whisperkit"
    public static let backendWhisperCpp = "whisper.cpp"
    public static let backendMLXAudio = "mlx-audio"
    public static let backendFluidParakeet = "fluid-parakeet"
    public static let backendFluidParaformer = "fluid-paraformer"
    public static let backendFluidSenseVoice = "fluid-sensevoice"
    public static let backendAppleSpeech = "apple-speech"

    static let whisperSizes: [(size: String, memoryGB: Double)] = [
        ("tiny", 1.0), ("base", 1.5), ("small", 2.5),
        ("medium", 5.0), ("large-v3-turbo", 6.0), ("large-v3", 10.0),
    ]

    public static let rows: [ModelRow] =
        existingBackendRows + fluidParakeetRows + chineseFamilyRows + appleSpeechRows
        + mlxAudioRows

    /// Every catalog row for one model under one runtime.
    ///
    /// More than one row is normal and correct — they are quantization
    /// variants of the *same* model, in preference order. What can no longer
    /// happen is a row belonging to a different model (#183): the lookup key
    /// is the identity, so `canary 1b` cannot answer for `mms 1b`.
    public static func rows(backend: String, identity: ModelID) -> [ModelRow] {
        rows.filter { $0.backend == backend && $0.identity == identity }
    }

    /// The preferred variant of one model under one runtime.
    public static func row(backend: String, identity: ModelID) -> ModelRow? {
        rows(backend: backend, identity: identity).first
    }

    /// Rows whose identity a user-supplied model string could name.
    ///
    /// `family/size` names exactly one identity. A bare size names every
    /// family publishing that size — which under mlx-audio is genuinely more
    /// than one. Returning them all is what lets a caller *say* the input was
    /// ambiguous, instead of taking the first and saying nothing (#65's
    /// "first row wins", now retired).
    public static func rows(backend: String, matching input: String) -> [ModelRow] {
        if let slash = input.firstIndex(of: "/") {
            guard let identity = ModelID(
                family: String(input[..<slash]),
                size: String(input[input.index(after: slash)...]))
            else { return [] }
            return rows(backend: backend, identity: identity)
        }
        return rows.filter { $0.backend == backend && $0.size == input }
    }

    /// Sizes the catalog has since renamed, by family.
    ///
    /// A stored key keeps its old spelling forever — this says what that
    /// spelling MEANS. `mlx-audio parakeet 0.6b` and `fluid-parakeet parakeet
    /// 0.6b-v3` both pin `parakeet-tdt-0.6b-v3`; the catalog now names the
    /// version its pin resolves to, and the 15 measurements taken under the
    /// abbreviation resolve to the same model rather than to a second one.
    static let renamedSizes: [String: [String: String]] = [
        "parakeet": ["0.6b": "0.6b-v3"]
    ]

    /// What a stored four-segment key means in today's catalog (#183).
    ///
    /// This is what lets the catalog carry true values **without rewriting a
    /// single stored key**. Round 4's CRITICAL was that assigning real
    /// quantizations rotates 19 of 37 keys while 344 of 383 measurements keep
    /// the old ones, so every affected candidate appeared twice in the ranking
    /// pool under one displayed name. Canonicalising on READ collapses them:
    /// the file is untouched, and both spellings resolve to one identity.
    ///
    /// Three transformations, and between them they cover all 25 keys the
    /// store actually holds:
    ///
    /// - **`family == size`** — the flat cache had no family, so it repeated
    ///   the size. That era was whisper-only (#14).
    /// - **A renamed size** — see ``renamedSizes``.
    /// - **The removed placeholder as a quantization** — it never named a
    ///   value; it meant "unrecorded". What it stood for is whatever the
    ///   catalog row for this model now states, and `.unknown` when no row
    ///   claims it.
    ///
    /// Returns `nil` only when the segments name no model at all.
    public static func canonical(
        backend: String, family: String, size: String, quantization: String
    ) -> (identity: ModelID, quantization: Quantization)? {
        let family = family == size ? "whisper" : family
        let size = renamedSizes[family]?[size] ?? size
        guard let identity = ModelID(family: family, size: size) else { return nil }
        guard quantization == ModelID.removedPlaceholder else {
            return (identity, Quantization(serialised: quantization))
        }
        return (identity, row(backend: backend, identity: identity)?.quantization ?? .unknown)
    }

    /// How a model is addressed: `family/size`, always, for every runtime.
    ///
    /// **Runtime-independent by construction** — which is the point. #183's
    /// third EXPECTED is that changing the runtime and changing the model are
    /// different acts. Two earlier rules both failed it: "is this mlx-audio?"
    /// obviously, and "is this size unambiguous under this runtime?" subtly —
    /// under whisperkit `base` resolves to `whisper/base`, under mlx-audio it
    /// resolves to `moonshine/base`, and both are unambiguous *within their own
    /// runtime*, so both addressed as the bare `base`. Keeping the model string
    /// and changing `--backend` silently changed the model (round-6 verify).
    ///
    /// A canonical address does not ask which runtime is hosting. The runtime
    /// is a separate field, which is what the whole change is about.
    public static func address(for identity: ModelID) -> String {
        "\(identity.family)/\(identity.size)"
    }

    /// How one runtime's own API spells a model.
    ///
    /// A CLOSED enumeration of runtimes, not a rule to infer from. Round 8
    /// shipped the rule `engineName = identity.size` — universally true of
    /// every runtime anyone checked, and false for mlx-audio, which publishes
    /// two families at `1b` and therefore spells models `canary/1b`. A rule
    /// whose counterexample nobody looked at is indistinguishable from a
    /// correct one, so this is data, per-runtime, and a test asserts every
    /// backend appears.
    public enum EngineVocabulary: Sendable {
        /// The runtime names models by size alone (`large-v3-turbo`).
        case size
        /// The runtime's own name IS the address (`canary/1b`).
        case address
    }

    public static let engineVocabularies: [String: EngineVocabulary] = [
        backendWhisperKit: .size,
        backendWhisperCpp: .size,
        backendFluidParakeet: .size,
        backendFluidParaformer: .size,
        backendFluidSenseVoice: .size,
        // No model string reaches Speech.framework at all; `.size` is the
        // narrower claim and nothing observes it.
        backendAppleSpeech: .size,
        backendMLXAudio: .address,
    ]

    /// The name `backend`'s own API uses for the model `address` names.
    ///
    /// The address (`family/size`) is OURS — runtime-independent, identity
    /// level, what a store key and a `--model` argument carry. A vendor SDK
    /// wants its own vocabulary: WhisperKit's catalog says `large-v3-turbo`,
    /// not `whisper/large-v3-turbo`, and handing it the address fails to load.
    ///
    /// Call this INSIDE the engine, at the point that loads the model. Round 8
    /// put the translation at the caller instead, where installing it is
    /// optional and forgetting it is silent — and it was installed at one of
    /// its two call sites. An engine that skips it cannot load anything.
    ///
    /// A string that names no single model passes through untouched: it may be
    /// an external adapter's own vocabulary, and inventing a translation for
    /// something we cannot place would be guessing.
    public static func engineName(backend: String, address: String) -> String {
        guard case .resolved(let identity) = identity(backend: backend, matching: address),
              let vocabulary = engineVocabularies[backend]
        else { return address }
        switch vocabulary {
        case .size: return identity.size
        case .address: return self.address(for: identity)
        }
    }

    /// Rows split into those a measurement may be compared against and those
    /// whose identity is too incomplete to be one (#183).
    ///
    /// A row whose quantization is `unknown` names an artifact nobody can
    /// point at: two runs of it could have used different weights and the
    /// record would look identical. Such a row stays listable — it is still
    /// reference information — but it does not enter candidate enumeration.
    /// Both halves are returned because "excluded" must be sayable: dropping
    /// rows and not saying so reads exactly like having none.
    public static func comparable(
        backend: String, priorityCeiling: Int?
    ) -> (rows: [ModelRow], excluded: [ModelRow]) {
        let all = rows(backend: backend, priorityCeiling: priorityCeiling)
        return (all.filter { $0.quantization.isComplete },
                all.filter { !$0.quantization.isComplete })
    }

    /// Why a row was left out of candidate enumeration, in one line naming it.
    public static func exclusionNote(for row: ModelRow) -> String {
        "excluded '\(row.identity)' on \(row.backend): its quantization is unrecorded, "
            + "so a measurement of it could not be compared with another (#183)"
    }

    /// What a user's model string names under one runtime.
    ///
    /// Three outcomes, not two. This used to return `ModelID?`, collapsing
    /// "names nothing" and "names several" into one `nil` — and every caller
    /// then inherited whatever the collapse implied, without having to say
    /// what it wanted. That collapse is behind the lost supply-chain pin
    /// (`ExternalProcessEngine` cannot tell "no pin exists" from "two pins
    /// compete") and behind a language gate that read an unplaceable model as
    /// an unrestricted one. Returning three values makes each caller state its
    /// position on ambiguity instead of receiving one by default.
    public enum Resolution: Equatable, Sendable {
        /// Exactly one model. The only case that may be acted on.
        case resolved(ModelID)
        /// No model in this runtime's catalog answers to the string. It may be
        /// an external adapter's own vocabulary — unknown is not invalid.
        case unknown
        /// More than one model answers to it, so it names none of them.
        /// Carries the candidates so a caller can say WHICH, rather than only
        /// that it refused.
        case ambiguous([ModelID])
    }

    /// The model a user's string names under this runtime — or the reason it
    /// names no single one. Refusing to choose is the point.
    public static func identity(backend: String, matching input: String) -> Resolution {
        let named = Set(rows(backend: backend, matching: input).map(\.identity))
        switch named.count {
        case 0: return .unknown
        case 1: return .resolved(named.first!)
        default: return .ambiguous(named.sorted { address(for: $0) < address(for: $1) })
        }
    }

    /// Live rows for the fluid-parakeet backend (#35, spec model-grid
    /// "Full-family catalog"): the first non-Whisper family with a bundled
    /// engine. Distinct from the mlx-audio parakeet REFERENCE row — same
    /// family, different backend id, and this one enumerates as a benchmark
    /// candidate. Model weights are managed by the pinned FluidAudio release
    /// (SwiftPM exact: 0.15.4 is the supply-chain anchor; no per-file HF
    /// revision pin at this layer). `verified` = live-measured on-device
    /// (2026-07-06, task 4.1: WER 0.0% / 161.6x realtime on the en probe;
    /// the repo id is the one FluidAudio actually downloaded from).
    static let fluidParakeetRows: [ModelRow] = [
        ModelRow(
            backend: backendFluidParakeet, family: "parakeet", size: "0.6b-v3",
            quantization: .named("int8"), hfRepo: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
            // #105: parakeet-tdt-0.6b-v3 is English + 24 European languages
            // (NVIDIA model card) — NOT blanket multilingual. The earlier
            // "multi" label let the router propose it for zh/ja/ko audio.
            languages: [
                "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu",
                "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
            ],
            estMemoryGB: 2.0, priority: 1, verified: true)
    ]

    /// Live rows for the Chinese families (#50, spec model-grid "Full-family
    /// catalog"), states set by the zh-TW live measurement (task 3.1,
    /// 2026-07-06, cv-zhtw suite):
    ///
    /// - sensevoice small: mean CER 0.1941 vs whisperkit large-v3-turbo
    ///   0.1791 on the same corpora — near-parity with a far larger model at
    ///   ~6x realtime and ~1.1 GB peak. Verified, priority 1. Output script
    ///   is Simplified (metric comparison folds Han, #34 D7; delivery-script
    ///   preference is a separate concern).
    /// - paraformer large-zh: FluidAudio 0.15.4 emits un-detokenized BPE
    ///   subwords ("n@@个s@@…的的的…", CER 1.67-2.07) — unusable until the
    ///   upstream decode bug is fixed. Wiring kept, priority 2 so the default
    ///   benchmark sweep never pays its download; no repo id on an
    ///   unverified row (invariant).
    static let chineseFamilyRows: [ModelRow] = [
        ModelRow(
            backend: backendFluidParaformer, family: "paraformer", size: "large-zh",
            quantization: .named("fp16"),
            languages: ["zh"], estMemoryGB: 2.5, priority: 2, verified: false),
        ModelRow(
            backend: backendFluidSenseVoice, family: "sensevoice", size: "small",
            quantization: .named("fp16"), hfRepo: "FluidInference/sensevoice-small-coreml",
            languages: ["multi"], estMemoryGB: 1.5, priority: 1, verified: true),
    ]

    /// The OS-native Apple Speech row (#121, spec model-grid "Full-family
    /// catalog"). Every field here differs in KIND from the other live rows,
    /// so each choice is recorded rather than copied:
    ///
    /// - `family` "speechanalyzer": Apple publishes no model name — the only
    ///   honest handle is the framework surface that exposes it
    ///   (`SpeechAnalyzer` + `SpeechTranscriber`). Inventing a weight name
    ///   would be a guess dressed as a fact.
    /// - `size` "system": there is no user-selectable size and no weight file.
    ///   The model is whatever the installed OS ships, so the address names
    ///   its provenance instead of a nonexistent parameter count. "system" is
    ///   unique across the grid, so it collides with nothing in the registry's
    ///   bare-size memory map or in `--model` resolution.
    /// - `hfRepo`/`hfRevision` nil: nothing is fetched from HuggingFace. The
    ///   supply-chain pin for this backend is the OS version itself.
    /// - `languages`: the 25 base subtags of the 45 locales
    ///   `SpeechTranscriber.supportedLocales` reported on macOS 27 (probed
    ///   2026-08-01). NOT "multi" — that sentinel is reserved for the
    ///   99+/1000+ class (ModelRow doc comment), and #105 is the standing
    ///   lesson about what mislabeling a bounded set costs: a 25-language
    ///   parakeet labeled "multi" got proposed for zh/ja/ko audio. Note `mul`
    ///   is ISO 639-2 "multiple languages" (Apple's `mul_IN` locale) — a real
    ///   advertised subtag, NOT this field's "multi" sentinel.
    /// - `estMemoryGB` 2.0: **UNMEASURED PLACEHOLDER.** Apple exposes no model
    ///   footprint and this project has not measured one; 2.0 sits with the
    ///   other on-device CoreML/ANE speech rows (parakeet 2.0, paraformer 2.5)
    ///   and is deliberately conservative, since the value only ever gates
    ///   cold-start feasibility (design D2: measured data wins once benchmarked).
    /// - `priority` 1: the tier gates the DEFAULT benchmark sweep, and there is
    ///   nothing to defer for the measured set — en_* and zh_* assets were
    ///   pre-installed on the development machine (ja_JP was NOT, and had to be
    ///   downloaded; "no download" is not a property of this backend), and on
    ///   a host below macOS 26 `isAvailable()` returns false so enumeration
    ///   skips it with a note. Paraformer sits at 2 because its output is
    ///   unusable, not merely because it downloads (whisperkit rows are
    ///   priority 1 and download on first use). A first-class competitor across
    ///   all three benchmark languages belongs in the first-run set.
    /// - `verified` false: the flag means live-measured on this project's
    ///   corpora (ModelGridTests: "verified false until benchmarked"). Ad-hoc
    ///   probes proved the API works; they are not a `bestasr benchmark` run,
    ///   so the honest value is false. It also satisfies the other reading of
    ///   the field (hf repo checked against the hub) vacuously — there is no
    ///   repo, and the grid invariant forbids a repo id on an unverified row.
    static let appleSpeechRows: [ModelRow] = [
        ModelRow(
            backend: backendAppleSpeech, family: "speechanalyzer", size: "system",
            quantization: .notApplicable,
            languages: [
                "bn", "de", "en", "es", "fr", "gu", "hi", "it", "ja", "kn", "ko", "ks",
                "mai", "ml", "mr", "mul", "ne", "or", "pa", "pt", "ta", "te", "ur",
                "yue", "zh",
            ],
            estMemoryGB: 2.0, priority: 1, verified: false)
    ]

    /// Existing backends: live-validated all session — verified, priority 1.
    static let existingBackendRows: [ModelRow] = {
        var rows: [ModelRow] = []
        for (size, memory) in whisperSizes {
            rows.append(ModelRow(
                backend: backendWhisperKit, family: "whisper", size: size,
                quantization: .deferred(.runtime), languages: ["multi"],
                estMemoryGB: memory, priority: 1, verified: true))
            // whisper.cpp quant availability mirrors the HF distribution (#5).
            let quants: [Quantization]
            switch size {
            case "tiny", "base", "small": quants = [.named("q5_1"), .named("q8_0")]
            case "large-v3": quants = [.named("q5_0")]
            default: quants = [.named("q5_0"), .named("q8_0")]
            }
            for quant in quants {
                rows.append(ModelRow(
                    backend: backendWhisperCpp, family: "whisper", size: size,
                    quantization: quant, languages: ["multi"],
                    estMemoryGB: memory / 2, priority: 1, verified: true))
            }
        }
        return rows
    }()

    /// All 15 mlx-audio STT families — reference catalog (spec: Full-family
    /// catalog; #20: backend not bundled).
    static let mlxAudioRows: [ModelRow] = [
        // ── priority 1: first-run set (design D5)
        // openai original (ships the processor config); the mlx-community
        // conversions lack preprocessor_config.json and fail mlx_audio's
        // whisper loader — live-probed 2026-07-02.
        ModelRow(backend: backendMLXAudio, family: "whisper", size: "large-v3-turbo",
                 quantization: .unknown, hfRepo: "openai/whisper-large-v3-turbo",
                 hfRevision: "41f01f3fe87f28c78e2fbf8b568835947dd65ed9",
                 languages: ["multi"], estMemoryGB: 3.2, priority: 1, verified: true),
        // size is the version this row's own pin resolves to (#183 D3). The
        // 15 measurements stored under `0.6b` are not orphaned: they
        // canonicalise to `0.6b-v3` on read (see `renamedSizes`), so the file
        // stays untouched and the two parakeet rows become one model — which
        // is #183's second EXPECTED.
        ModelRow(backend: backendMLXAudio, family: "parakeet", size: "0.6b-v3",
                 quantization: .unknown, hfRepo: "mlx-community/parakeet-tdt-0.6b-v3",
                 hfRevision: "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15",
                 // #105: same parakeet-tdt-0.6b-v3 weights — European set, not "multi".
                 languages: [
                     "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu",
                     "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
                 ],
                 estMemoryGB: 1.5, priority: 1, verified: true),
        ModelRow(backend: backendMLXAudio, family: "qwen3-asr", size: "small",
                 quantization: .named("4bit"), hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 2.0, priority: 1, verified: false),
        ModelRow(backend: backendMLXAudio, family: "moonshine", size: "base",
                 quantization: .unknown, hfRepo: "UsefulSensors/moonshine-base",
                 hfRevision: "7a73d8d55ac0ba2ef3ae761593f6784b51f96dcf",
                 languages: ["en"], estMemoryGB: 0.4, priority: 1, verified: true),
        // ── priority 2: one representative per remaining family
        ModelRow(backend: backendMLXAudio, family: "distil-whisper", size: "large-v3",
                 quantization: .unknown, hfRepo: nil,
                 languages: ["en"], estMemoryGB: 1.6, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "canary", size: "1b",
                 quantization: .named("q8"), hfRepo: "Mediform/canary-1b-v2-mlx-q8",
                 hfRevision: "0b6b32ee10f30c89e3ead7249bb636445e3019ee",
                 languages: ["multi"], estMemoryGB: 1.4, priority: 2, verified: true),
        ModelRow(backend: backendMLXAudio, family: "mms", size: "1b",
                 quantization: .unknown, hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 1.6, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "granite-speech", size: "2b",
                 quantization: .named("4bit"), hfRepo: "mlx-community/granite-speech-4.1-2b-nar-mlx",
                 hfRevision: "6acb7892068dd30227f20aba6eb7c4b0ae5c7e7c",
                 languages: ["multi"], estMemoryGB: 1.6, priority: 2, verified: true),
        ModelRow(backend: backendMLXAudio, family: "nemotron-asr", size: "streaming",
                 quantization: .unknown, hfRepo: "mlx-community/nemotron-3.5-asr-streaming-0.6b",
                 hfRevision: "e550040c0478027ed679b2b6b0d055502c103663",
                 languages: ["multi"], estMemoryGB: 2.0, priority: 2, verified: true),
        ModelRow(backend: backendMLXAudio, family: "voxtral", size: "mini-3b",
                 quantization: .named("4bit"), hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 2.2, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "qwen2-audio", size: "7b",
                 quantization: .named("4bit"), hfRepo: "mlx-community/Qwen2-Audio-7B-Instruct-4bit",
                 hfRevision: "c65570002626f41b4dc08b7b54f42f99f3e82e7f",
                 languages: ["multi"], estMemoryGB: 4.5, priority: 2, verified: true),
        ModelRow(backend: backendMLXAudio, family: "mega-asr", size: "default",
                 quantization: .unknown, hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 2.0, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "qwen3-forcedaligner", size: "default",
                 quantization: .unknown, hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 1.0, priority: 2, verified: false),
        // ── priority 3: deferred / large
        ModelRow(backend: backendMLXAudio, family: "vibevoice-asr", size: "9b",
                 quantization: .named("4bit"), hfRepo: "mlx-community/VibeVoice-ASR-4bit",
                 hfRevision: "a1a15cb6c7b70f76b588af7e12f6fab34d5ab654",
                 languages: ["multi"], estMemoryGB: 5.5, priority: 3, verified: true),
        ModelRow(backend: backendMLXAudio, family: "voxtral", size: "small-24b",
                 quantization: .named("4bit"), hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 13.0, priority: 3, verified: false),
        ModelRow(backend: backendMLXAudio, family: "voxtral-realtime", size: "4b",
                 quantization: .named("4bit"), hfRepo: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
                 hfRevision: "fdebf7b2af834a1db4b8a3c99ab7480b333adf9e",
                 languages: ["multi"], estMemoryGB: 2.6, priority: 3, verified: true),
    ]

    /// Grid query used by benchmark enumeration (spec: Priority tiers gate the
    /// default sweep). `priorityCeiling` nil = no gate (--all-grid).
    public static func rows(backend: String, priorityCeiling: Int? = 1) -> [ModelRow] {
        rows.filter { row in
            row.backend == backend
                && (priorityCeiling.map { row.priority <= $0 } ?? true)
        }
    }

    /// Distinct mlx-audio family names — the 15-family completeness anchor.
    public static var mlxFamilies: Set<String> {
        Set(mlxAudioRows.map(\.family))
    }
}
