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

    /// Estimated unified-memory requirement (GB) per model — projected from
    /// the model grid's whisperkit rows (fp16-weight upper bounds; quantized
    /// variants use less, so the gate is conservative).
    private static var memoryEstimates: [String: Double] {
        Dictionary(uniqueKeysWithValues: ModelGrid.rows
            .filter { $0.backend == ModelGrid.backendWhisperKit }
            .map { ($0.size, $0.estMemoryGB) })
    }

    /// Candidate models per profile (design brief §7.4, carried into the
    /// cold-start prior spec).
    public static let profileModels: [RouterProfile: [String]] = [
        .fast: ["tiny", "base", "small"],
        .balanced: ["small", "medium"],
        .accurate: ["medium", "large-v3-turbo", "large-v3"],
    ]

    /// Quantization variants offered per (backend, model). WhisperKit models
    /// are CoreML bundles published per-variant ("default" = standard build).
    /// whisper.cpp rows mirror the actual ggerganov/whisper.cpp HF file list
    /// (probed 2026-07-02, #5): tiny/base/small ship q5_1 (q5_0 is 404),
    /// medium/large-tier ship q5_0, and large-v3 has no q8_0. A wrong row
    /// here turns the engine's download guidance into a dead URL.
    public static func quantizations(for backend: BackendID, model: String) -> [String] {
        // Projected from the model grid (the single catalog, #14): unknown
        // models yield no rows — same drift guard as before, one source now.
        ModelGrid.rows
            .filter { $0.backend == backend.rawValue && $0.size == model }
            .map(\.quantization)
    }

    /// The quantization the cold-start prior assumes — the first (preferred)
    /// variant, so a recommendation can never name a file HF does not host.
    public static func defaultQuantization(for backend: BackendID, model: String) -> String {
        guard let first = quantizations(for: backend, model: model).first else {
            preconditionFailure("no quantization row for \(backend.rawValue) \(model) — add one to ModelRegistry.quantizations(for:model:)")
        }
        return first
    }

    public static func isSupportedModel(_ name: String) -> Bool {
        supportedModels.contains(name)
    }

    /// Static memory estimate for cold-start feasibility (spec asr-engine:
    /// Estimate model requirements). Unknown model names are a caller bug.
    public static func requirements(for model: String) throws -> ModelRequirements {
        if let memoryGB = memoryEstimates[model] {
            return ModelRequirements(model: model, memoryGB: memoryGB)
        }
        throw BestASRError.usage(
            "unknown model: '\(model)'; run list-models for the catalog"
        )
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
