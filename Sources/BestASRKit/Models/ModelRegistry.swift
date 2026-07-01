import Foundation

/// Catalog of supported models, per-backend quantization variants, static
/// memory estimates, and profile candidate lists.
///
/// The memory figures are coarse cold-start feasibility gates, not measured
/// benchmarks — measured data always wins once `bestasr benchmark` has run
/// (design D2). They are centralized here so recalibration touches one place.
public enum ModelRegistry {
    /// Whisper-family model sizes, smallest to largest.
    public static let supportedModels: [String] = [
        "tiny", "base", "small", "medium", "large-v3-turbo", "large-v3",
    ]

    /// Memory-downgrade order, largest first (design: cold-start prior).
    public static let downgradeChain: [String] = [
        "large-v3", "medium", "small", "base", "tiny",
    ]

    /// Estimated unified-memory requirement (GB) per model — fp16-weight
    /// upper bounds; quantized variants use less, so the gate is conservative.
    private static let memoryEstimates: [String: Double] = [
        "tiny": 1.0,
        "base": 1.5,
        "small": 2.5,
        "medium": 5.0,
        "large-v3-turbo": 6.0,
        "large-v3": 10.0,
    ]

    /// Candidate models per profile (design brief §7.4, carried into the
    /// cold-start prior spec).
    public static let profileModels: [RouterProfile: [String]] = [
        .fast: ["tiny", "base", "small"],
        .balanced: ["small", "medium"],
        .accurate: ["medium", "large-v3-turbo", "large-v3"],
    ]

    /// Quantization variants offered per backend. WhisperKit models are CoreML
    /// bundles published per-variant ("default" maps to the standard build);
    /// whisper.cpp GGUF files come in explicit quantization levels.
    public static let quantizations: [BackendID: [String]] = [
        .whisperKit: ["default"],
        .whisperCpp: ["q5_0", "q8_0"],
    ]

    /// The quantization the cold-start prior assumes for a backend.
    public static func defaultQuantization(for backend: BackendID) -> String {
        switch backend {
        case .whisperKit: "default"
        case .whisperCpp: "q5_0"
        }
    }

    public static func isSupportedModel(_ name: String) -> Bool {
        supportedModels.contains(name)
    }

    /// Static memory estimate for cold-start feasibility (spec asr-engine:
    /// Estimate model requirements). Unknown model names are a caller bug.
    public static func requirements(for model: String) throws -> ModelRequirements {
        guard let memoryGB = memoryEstimates[model] else {
            throw BestASRError.usage(
                "unknown model: '\(model)'; supported models are \(supportedModels.joined(separator: ", "))"
            )
        }
        return ModelRequirements(model: model, memoryGB: memoryGB)
    }

    /// Accuracy prior used only to order candidates within a profile list
    /// (most-accurate-that-fits wins in the cold-start prior).
    public static func accuracyRank(of model: String) -> Int {
        supportedModels.firstIndex(of: model) ?? -1
    }

    /// The next smaller model in the downgrade chain, or nil at the end.
    /// large-v3-turbo is a large-tier model whose downgrade successor is medium.
    public static func nextSmaller(than model: String) -> String? {
        if model == "large-v3-turbo" { return "medium" }
        guard let idx = downgradeChain.firstIndex(of: model), idx + 1 < downgradeChain.count else {
            return nil
        }
        return downgradeChain[idx + 1]
    }
}
