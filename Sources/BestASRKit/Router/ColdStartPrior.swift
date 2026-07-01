import Foundation

/// Static prior used when no usable benchmark record exists (spec asr-routing:
/// Cold-start prior when no benchmark data exists; design D2). Logic carried
/// over from the archived Python MVP, minus the cross-platform axes.
public enum ColdStartPrior {
    /// whisperkit first, then whisper.cpp (spec order), among available backends.
    public static func selectBackend(
        available: [BackendID],
        hasANE: Bool?
    ) -> (backend: BackendID, reasons: [String]) {
        if available.contains(.whisperKit) {
            var reasons = ["whisperkit preferred on Apple Silicon (CoreML path)"]
            if hasANE == true {
                reasons.append("Apple Neural Engine available for CoreML acceleration")
            }
            return (.whisperKit, reasons)
        }
        return (
            .whisperCpp,
            ["whisper.cpp selected: whisperkit unavailable on this host"]
        )
    }

    /// The most accurate model in the profile's candidate list whose estimated
    /// requirement fits unified memory; when nothing fits, start from the
    /// smallest candidate and walk the downgrade chain.
    public static func selectModel(
        profile: RouterProfile,
        unifiedMemoryGB: Double
    ) -> (model: String, reasons: [String], warnings: [String]) {
        let candidates = ModelRegistry.profileModels[profile] ?? []
        let feasible = candidates.filter { fits($0, in: unifiedMemoryGB) }
        if let best = feasible.max(by: {
            ModelRegistry.accuracyRank(of: $0) < ModelRegistry.accuracyRank(of: $1)
        }) {
            return (best, ["\(profile.rawValue) profile selected '\(best)'"], [])
        }

        let smallest = candidates.min(by: {
            ModelRegistry.accuracyRank(of: $0) < ModelRegistry.accuracyRank(of: $1)
        }) ?? "tiny"
        var reasons = [
            "no '\(profile.rawValue)' profile model fits ~\(short(unifiedMemoryGB)) GB; "
                + "starting from '\(smallest)'"
        ]
        let (finalModel, warnings, downgradeReasons) = ensureFits(
            smallest, in: unifiedMemoryGB)
        reasons += downgradeReasons
        return (finalModel, reasons, warnings)
    }

    /// Downgrade along large-v3 → medium → small → base → tiny until the model
    /// fits, one warning and reason per step (spec asr-routing: Downgrade model
    /// when memory is insufficient — cold-start only).
    public static func ensureFits(
        _ model: String,
        in unifiedMemoryGB: Double
    ) -> (model: String, warnings: [String], reasons: [String]) {
        var current = model
        var warnings: [String] = []
        var reasons: [String] = []
        while !fits(current, in: unifiedMemoryGB) {
            guard let next = ModelRegistry.nextSmaller(than: current) else {
                warnings.append(
                    "even '\(current)' may not fit ~\(short(unifiedMemoryGB)) GB unified memory; "
                        + "using it anyway"
                )
                break
            }
            let need = (try? ModelRegistry.requirements(for: current).memoryGB) ?? 0
            warnings.append(
                "'\(current)' needs ~\(short(need)) GB but only ~\(short(unifiedMemoryGB)) GB "
                    + "unified memory available; downgrading to '\(next)'"
            )
            reasons.append("downgraded '\(current)' to '\(next)' to fit unified memory")
            current = next
        }
        return (current, warnings, reasons)
    }

    static func fits(_ model: String, in memoryGB: Double) -> Bool {
        guard let requirement = try? ModelRegistry.requirements(for: model) else { return false }
        return requirement.memoryGB <= memoryGB
    }

    private static func short(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
