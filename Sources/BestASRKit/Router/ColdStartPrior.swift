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
    ) -> (identity: ModelID, reasons: [String], warnings: [String]) {
        let candidates = ModelRegistry.profileModels[profile] ?? []
        // Returns the MODEL, not a spelling of it. Flattening to `.size` here
        // is what let a bare size travel all the way to the engine while every
        // layer in between believed it was passing an address (#183, round-8
        // verify) — the caller could not have restored the family, because by
        // then there was nothing left saying which family it was.
        let feasible = candidates.filter { fits($0, in: unifiedMemoryGB) }
        if let best = feasible.max(by: {
            ModelRegistry.accuracyRank(of: $0) < ModelRegistry.accuracyRank(of: $1)
        }) {
            return (best, ["\(profile.rawValue) profile selected '\(best.size)'"], [])
        }

        let smallest = candidates.min(by: {
            ModelRegistry.accuracyRank(of: $0) < ModelRegistry.accuracyRank(of: $1)
        }) ?? ModelID(family: "whisper", size: "tiny")!
        var reasons = [
            "no '\(profile.rawValue)' profile model fits ~\(short(unifiedMemoryGB)) GB; "
                + "starting from '\(smallest.size)'"
        ]
        let (finalModel, warnings, downgradeReasons) = ensureFits(
            smallest, in: unifiedMemoryGB)
        reasons += downgradeReasons
        return (finalModel, reasons, warnings)
    }

    /// Downgrade along large-v3 → medium → small → base → tiny until the model
    /// fits, one warning and reason per step (spec asr-routing: Downgrade model
    /// when memory is insufficient — cold-start only).
    /// - Parameter hostedBy: when the user locked a runtime, the walk stays
    ///   inside what that runtime actually offers. `nil` keeps the family-wide
    ///   walk, which is right for the cold-start path where no backend is
    ///   locked yet.
    public static func ensureFits(
        _ model: ModelID,
        in unifiedMemoryGB: Double,
        hostedBy backend: String? = nil
    ) -> (model: ModelID, warnings: [String], reasons: [String]) {
        var current = model
        var warnings: [String] = []
        var reasons: [String] = []
        while !fits(current, in: unifiedMemoryGB) {
            let step = backend.map { ModelRegistry.nextSmaller(than: current, hostedBy: $0) }
                ?? ModelRegistry.nextSmaller(than: current)
            guard let next = step else {
                warnings.append(
                    "even '\(current.size)' may not fit ~\(short(unifiedMemoryGB)) GB unified memory; "
                        + "using it anyway"
                )
                break
            }
            let need = (try? ModelRegistry.requirements(for: current).memoryGB) ?? 0
            warnings.append(
                "'\(current.size)' needs ~\(short(need)) GB but only ~\(short(unifiedMemoryGB)) GB "
                    + "unified memory available; downgrading to '\(next.size)'"
            )
            reasons.append("downgraded '\(current.size)' to '\(next.size)' to fit unified memory")
            current = next
        }
        return (current, warnings, reasons)
    }

    static func fits(_ model: ModelID, in memoryGB: Double) -> Bool {
        guard let requirement = try? ModelRegistry.requirements(for: model) else { return false }
        return requirement.memoryGB <= memoryGB
    }

    private static func short(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
