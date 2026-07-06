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

    static let whisperSizes: [(size: String, memoryGB: Double)] = [
        ("tiny", 1.0), ("base", 1.5), ("small", 2.5),
        ("medium", 5.0), ("large-v3-turbo", 6.0), ("large-v3", 10.0),
    ]

    public static let rows: [ModelRow] = existingBackendRows + fluidParakeetRows + chineseFamilyRows + mlxAudioRows

    /// Resolve a model ADDRESS to its row (#65): mlx-audio rows are
    /// addressed `family/size` (sizes collide across families — canary 1b vs
    /// mms 1b); every other backend addresses by bare size.
    public static func row(backend: String, modelAddress: String) -> ModelRow? {
        if let slash = modelAddress.firstIndex(of: "/") {
            let family = String(modelAddress[..<slash])
            let size = String(modelAddress[modelAddress.index(after: slash)...])
            return rows.first {
                $0.backend == backend && $0.family == family && $0.size == size
            }
        }
        return rows.first { $0.backend == backend && $0.size == modelAddress }
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
            quantization: "default", hfRepo: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
            languages: ["multi"], estMemoryGB: 2.0, priority: 1, verified: true)
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
            quantization: "default",
            languages: ["zh"], estMemoryGB: 2.5, priority: 2, verified: false),
        ModelRow(
            backend: backendFluidSenseVoice, family: "sensevoice", size: "small",
            quantization: "default", hfRepo: "FluidInference/sensevoice-small-coreml",
            languages: ["multi"], estMemoryGB: 1.5, priority: 1, verified: true),
    ]

    /// Existing backends: live-validated all session — verified, priority 1.
    static let existingBackendRows: [ModelRow] = {
        var rows: [ModelRow] = []
        for (size, memory) in whisperSizes {
            rows.append(ModelRow(
                backend: backendWhisperKit, family: "whisper", size: size,
                quantization: "default", languages: ["multi"],
                estMemoryGB: memory, priority: 1, verified: true))
            // whisper.cpp quant availability mirrors the HF distribution (#5).
            let quants: [String]
            switch size {
            case "tiny", "base", "small": quants = ["q5_1", "q8_0"]
            case "large-v3": quants = ["q5_0"]
            default: quants = ["q5_0", "q8_0"]
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
                 quantization: "default", hfRepo: "openai/whisper-large-v3-turbo",
                 hfRevision: "41f01f3fe87f28c78e2fbf8b568835947dd65ed9",
                 languages: ["multi"], estMemoryGB: 3.2, priority: 1, verified: true),
        ModelRow(backend: backendMLXAudio, family: "parakeet", size: "0.6b",
                 quantization: "default", hfRepo: "mlx-community/parakeet-tdt-0.6b-v3",
                 hfRevision: "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15",
                 languages: ["multi"], estMemoryGB: 1.5, priority: 1, verified: true),
        ModelRow(backend: backendMLXAudio, family: "qwen3-asr", size: "small",
                 quantization: "4bit", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 2.0, priority: 1, verified: false),
        ModelRow(backend: backendMLXAudio, family: "moonshine", size: "base",
                 quantization: "default", hfRepo: "UsefulSensors/moonshine-base",
                 hfRevision: "7a73d8d55ac0ba2ef3ae761593f6784b51f96dcf",
                 languages: ["en"], estMemoryGB: 0.4, priority: 1, verified: false),
        // ── priority 2: one representative per remaining family
        ModelRow(backend: backendMLXAudio, family: "distil-whisper", size: "large-v3",
                 quantization: "default", hfRepo: nil,
                 languages: ["en"], estMemoryGB: 1.6, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "canary", size: "1b",
                 quantization: "default", hfRepo: "Mediform/canary-1b-v2-mlx-q8",
                 hfRevision: "0b6b32ee10f30c89e3ead7249bb636445e3019ee",
                 languages: ["multi"], estMemoryGB: 1.4, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "mms", size: "1b",
                 quantization: "default", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 1.6, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "granite-speech", size: "2b",
                 quantization: "4bit", hfRepo: "mlx-community/granite-speech-4.1-2b-nar-mlx",
                 hfRevision: "6acb7892068dd30227f20aba6eb7c4b0ae5c7e7c",
                 languages: ["multi"], estMemoryGB: 1.6, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "nemotron-asr", size: "streaming",
                 quantization: "default", hfRepo: "mlx-community/nemotron-3.5-asr-streaming-0.6b",
                 hfRevision: "e550040c0478027ed679b2b6b0d055502c103663",
                 languages: ["multi"], estMemoryGB: 2.0, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "voxtral", size: "mini-3b",
                 quantization: "4bit", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 2.2, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "qwen2-audio", size: "7b",
                 quantization: "4bit", hfRepo: "mlx-community/Qwen2-Audio-7B-Instruct-4bit",
                 hfRevision: "c65570002626f41b4dc08b7b54f42f99f3e82e7f",
                 languages: ["multi"], estMemoryGB: 4.5, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "mega-asr", size: "default",
                 quantization: "default", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 2.0, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "qwen3-forcedaligner", size: "default",
                 quantization: "default", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 1.0, priority: 2, verified: false),
        // ── priority 3: deferred / large
        ModelRow(backend: backendMLXAudio, family: "vibevoice-asr", size: "9b",
                 quantization: "4bit", hfRepo: "mlx-community/VibeVoice-ASR-4bit",
                 hfRevision: "a1a15cb6c7b70f76b588af7e12f6fab34d5ab654",
                 languages: ["multi"], estMemoryGB: 5.5, priority: 3, verified: false),
        ModelRow(backend: backendMLXAudio, family: "voxtral", size: "small-24b",
                 quantization: "4bit", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 13.0, priority: 3, verified: false),
        ModelRow(backend: backendMLXAudio, family: "voxtral-realtime", size: "4b",
                 quantization: "4bit", hfRepo: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
                 hfRevision: "fdebf7b2af834a1db4b8a3c99ab7480b333adf9e",
                 languages: ["multi"], estMemoryGB: 2.6, priority: 3, verified: false),
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
