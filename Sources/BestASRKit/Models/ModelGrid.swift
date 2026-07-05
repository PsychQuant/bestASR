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

    static let whisperSizes: [(size: String, memoryGB: Double)] = [
        ("tiny", 1.0), ("base", 1.5), ("small", 2.5),
        ("medium", 5.0), ("large-v3-turbo", 6.0), ("large-v3", 10.0),
    ]

    public static let rows: [ModelRow] = existingBackendRows + fluidParakeetRows + mlxAudioRows

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
                 quantization: "default", hfRepo: nil,
                 languages: ["en"], estMemoryGB: 0.4, priority: 1, verified: false),
        // ── priority 2: one representative per remaining family
        ModelRow(backend: backendMLXAudio, family: "distil-whisper", size: "large-v3",
                 quantization: "default", hfRepo: nil,
                 languages: ["en"], estMemoryGB: 1.6, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "canary", size: "1b",
                 quantization: "default", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 1.4, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "mms", size: "1b",
                 quantization: "default", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 1.6, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "granite-speech", size: "2b",
                 quantization: "4bit", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 1.6, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "nemotron-asr", size: "streaming",
                 quantization: "default", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 2.0, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "voxtral", size: "mini-3b",
                 quantization: "4bit", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 2.2, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "qwen2-audio", size: "7b",
                 quantization: "4bit", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 4.5, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "mega-asr", size: "default",
                 quantization: "default", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 2.0, priority: 2, verified: false),
        ModelRow(backend: backendMLXAudio, family: "qwen3-forcedaligner", size: "default",
                 quantization: "default", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 1.0, priority: 2, verified: false),
        // ── priority 3: deferred / large
        ModelRow(backend: backendMLXAudio, family: "vibevoice-asr", size: "9b",
                 quantization: "4bit", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 5.5, priority: 3, verified: false),
        ModelRow(backend: backendMLXAudio, family: "voxtral", size: "small-24b",
                 quantization: "4bit", hfRepo: nil,
                 languages: ["multi"], estMemoryGB: 13.0, priority: 3, verified: false),
        ModelRow(backend: backendMLXAudio, family: "voxtral-realtime", size: "4b",
                 quantization: "4bit", hfRepo: nil,
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
