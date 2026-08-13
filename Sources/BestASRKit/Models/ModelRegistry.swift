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
    /// the model grid's live-engine rows (fp16-weight upper bounds; quantized
    /// variants use less, so the gate is conservative). Keyed by the whole
    /// identity: size names are NOT disjoint across families (sensevoice
    /// "small" vs whisper "small", #50), and the map used to resolve that by
    /// keeping the larger figure, which gave sensevoice whisper's estimate.
    private static var memoryEstimates: [ModelID: Double] {
        // No uniquing: the collision it existed to absorb was two *different*
        // models sharing a size name (sensevoice small vs whisper small, #50),
        // and keying by identity ends it. Every live-engine backend offers each
        // identity once, so a duplicate key here would now mean a real catalog
        // defect — and a trap is the right answer to that, not a silent max.
        Dictionary(
            uniqueKeysWithValues: ModelGrid.rows
                .filter {
                    $0.backend == ModelGrid.backendWhisperKit
                        || $0.backend == ModelGrid.backendFluidParakeet
                        || $0.backend == ModelGrid.backendFluidParaformer
                        || $0.backend == ModelGrid.backendFluidSenseVoice
                        // #121: the OS-native row registers here like every
                        // other live-engine backend. Its estimate is an
                        // UNMEASURED placeholder (see the grid row's comment).
                        || $0.backend == ModelGrid.backendAppleSpeech
                }
                .map { ($0.identity, $0.estMemoryGB) })
    }

    /// Candidate models per profile (design brief §7.4, carried into the
    /// cold-start prior spec).
    public static let profileModels: [RouterProfile: [ModelID]] = [
        .low: whisper("tiny", "base", "small"),
        .medium: whisper("small", "medium"),
        // The top three tiers share one list: without measured data the
        // ordinals can only differ in measured weighting (design D5, #29).
        .high: whisper("medium", "large-v3-turbo", "large-v3"),
        .xhigh: whisper("medium", "large-v3-turbo", "large-v3"),
        .max: whisper("medium", "large-v3-turbo", "large-v3"),
    ]

    /// Whisper-family identities from their size names. The profile lists are
    /// whisper-only today; naming the family here is what stops a size name
    /// from silently meaning some other family's model later (#183).
    private static func whisper(_ sizes: String...) -> [ModelID] {
        sizes.map { size in
            guard let identity = ModelID(family: "whisper", size: size) else {
                preconditionFailure("profile list names no model: whisper \(size)")
            }
            return identity
        }
    }

    /// Quantization variants offered per (backend, model). WhisperKit models
    /// are CoreML bundles it fetches itself, so their rows state
    /// `deferred(.runtime)` rather than a value (#183): upstream publishes 27
    /// named variants and `large-v3-turbo` alone maps to at least four,
    /// differing in checkpoint date and compression size.
    /// whisper.cpp rows mirror the actual ggerganov/whisper.cpp HF file list
    /// (probed 2026-07-02, #5): tiny/base/small ship q5_1 (q5_0 is 404),
    /// medium/large-tier ship q5_0, and large-v3 has no q8_0. A wrong row
    /// here turns the engine's download guidance into a dead URL.
    public static func quantizations(for backend: BackendID, model: String) -> [String] {
        // Projected from the model grid (the single catalog, #14): unknown
        // models yield no rows — same drift guard as before, one source now.
        // A string that names two models names none: returning canary's
        // variants for a bare "1b" would put mms's quantizations out of reach
        // and never say why (#183).
        guard let identity = ModelGrid.identity(backend: backend.rawValue, matching: model)
        else { return [] }
        return quantizations(for: backend, identity: identity)
    }

    /// Quantization variants of one model — no name resolution, so no way for
    /// the answer to belong to a different model.
    public static func quantizations(for backend: BackendID, identity: ModelID) -> [String] {
        ModelGrid.rows(backend: backend.rawValue, identity: identity)
            .map(\.quantization.serialised)
    }

    /// The quantization the cold-start prior assumes — the first (preferred)
    /// variant, so a recommendation can never name a file HF does not host.
    public static func defaultQuantization(for backend: BackendID, model: String) -> String {
        guard let first = quantizations(for: backend, model: model).first else {
            preconditionFailure(
                "\(backend.rawValue) \(model) yields no quantization row — either no row exists, "
                    + "or the name matches more than one model and cannot be resolved (#183)")
        }
        return first
    }

    /// The preferred variant of one model, asked for by identity.
    public static func defaultQuantization(for backend: BackendID, identity: ModelID) -> String? {
        quantizations(for: backend, identity: identity).first
    }

    public static func isSupportedModel(_ name: String) -> Bool {
        supportedModels.contains(name)
    }

    /// Whether a model name is runnable on ANY live-engine backend — whisper
    /// sizes plus live non-Whisper rows (#35). Reference rows (mlx-audio)
    /// stay excluded: no bundled backend can run them.
    public static func isRunnableModel(_ name: String, includeExternal: Bool = false) -> Bool {
        var liveNonWhisper: Set<String> = [
            ModelGrid.backendFluidParakeet, ModelGrid.backendFluidParaformer,
            ModelGrid.backendFluidSenseVoice,
            // #121: bundled like the fluid backends, so `--model system`
            // resolves. Unconditional (not gated on includeExternal) because
            // this engine ships in-process; the macOS-26 gate is availability,
            // which the router checks separately.
            ModelGrid.backendAppleSpeech,
        ]
        // A registered external adapter upgrades its catalog rows to
        // runnable (#51, spec asr-routing) — the caller passes availability.
        if includeExternal { liveNonWhisper.insert(ModelGrid.backendMLXAudio) }
        if isSupportedModel(name) { return true }
        // mlx-audio models are addressed family/size (#65) — resolve the
        // address instead of matching bare sizes (canary 1b vs mms 1b).
        if includeExternal,
            ModelGrid.rows(backend: ModelGrid.backendMLXAudio, matching: name)
                .contains(where: { $0.hfRepo != nil }) {
            return true
        }
        return ModelGrid.rows.contains {
            liveNonWhisper.contains($0.backend) && $0.size == name
        }
    }

    /// Static memory estimate for cold-start feasibility (spec asr-engine:
    /// Estimate model requirements). Unknown identities are a caller bug.
    ///
    /// Keyed by the whole identity, so `sensevoice small` no longer inherits
    /// `whisper small`'s figure — the two are different models that happen to
    /// share a size name (#50, #183).
    public static func requirements(for identity: ModelID) throws -> ModelRequirements {
        if let memoryGB = memoryEstimates[identity] {
            return ModelRequirements(model: identity.size, memoryGB: memoryGB)
        }
        throw BestASRError.usage(
            "unknown model: '\(identity)'; run list-models for the catalog"
        )
    }

    /// Estimate for a model named the way a user types it. Whisper sizes and
    /// the live non-whisper rows all have unique size names within the
    /// live-engine catalog, so a name still resolves — but it resolves through
    /// an identity rather than by indexing a bare-size map.
    public static func requirements(for model: String) throws -> ModelRequirements {
        guard let identity = liveIdentity(named: model) else {
            throw BestASRError.usage(
                "unknown model: '\(model)'; run list-models for the catalog")
        }
        return try requirements(for: identity)
    }

    /// The live-engine identity a bare size name refers to, or nil when none
    /// does — or when more than one does, which the catalog test forbids but
    /// the code must not assume away.
    static func liveIdentity(named model: String) -> ModelID? {
        // A bare size that is also a whisper size means whisper. That is what
        // `--model small` has always meant, and it is the family the default
        // backend serves. The old bare-size map reached the same answer by
        // accident — `uniquingKeysWith: max` kept whisper's 2.5 GB over
        // sensevoice's 1.5 only because it happened to be the larger number.
        // Stated, the rule survives a family whose estimate is larger.
        if supportedModels.contains(model),
           let whisper = ModelID(family: "whisper", size: model) {
            return whisper
        }
        let matches = Set(memoryEstimates.keys.filter { $0.size == model })
        return matches.count == 1 ? matches.first : nil
    }

    /// The accuracy prior, one ladder per family, ordered by estimated
    /// capacity (#183 D6).
    ///
    /// Before this, the prior was `supportedModels.firstIndex(of:)` — the
    /// whisper ladder — so every parakeet, paraformer, sensevoice and mlx
    /// model ranked -1 and sorted below everything, including below models
    /// they beat on measured accuracy. Ranking within the family is the same
    /// assumption the whisper ladder always encoded (more capacity, more
    /// accurate), now stated once and applied to all of them.
    ///
    /// The `max` here is NOT the one removed from `memoryEstimates`. That one
    /// hid two different models colliding on a size name; this one takes the
    /// larger figure when one model is offered at several precisions, which is
    /// the conservative reading for a feasibility prior.
    static var accuracyLadders: [String: [ModelID]] {
        let capacity = Dictionary(
            ModelGrid.rows.map { ($0.identity, $0.estMemoryGB) }, uniquingKeysWith: max)
        return Dictionary(grouping: capacity.keys, by: \.family).mapValues { identities in
            identities.sorted {
                (capacity[$0] ?? 0, $0.size) < (capacity[$1] ?? 0, $1.size)
            }
        }
    }

    /// Where this model sits in its own family's ladder, or -1 when the family
    /// is not in the catalog at all. Never -1 merely for not being whisper.
    public static func accuracyRank(of identity: ModelID) -> Int {
        accuracyLadders[identity.family]?.firstIndex(of: identity) ?? -1
    }

    /// Declared downgrade chains, largest first — deliberately NOT the same
    /// list as the accuracy ladder.
    ///
    /// whisper's chain omits `large-v3-turbo` because turbo is a peer of
    /// `large-v3`, not a step below it: both downgrade to `medium`. That
    /// distinction predates this change (#29) and is preserved rather than
    /// re-derived from memory figures, which would have quietly inserted turbo
    /// between large-v3 and medium.
    static let downgradeChains: [String: [String]] = [
        "whisper": downgradeChain
    ]

    /// The next model down its own family's chain, or nil at the foot of it.
    ///
    /// Downgrading across families would change what the model can do — a
    /// zh-only paraformer is not a smaller whisper — so the chain stays inside
    /// the family it started in. A family with no declared chain falls back to
    /// its capacity ladder, which for every current non-whisper family has a
    /// single member and therefore ends immediately.
    public static func nextSmaller(than identity: ModelID) -> ModelID? {
        if identity.family == "whisper", identity.size == "large-v3-turbo" {
            return ModelID(family: "whisper", size: "medium")
        }
        if let chain = downgradeChains[identity.family] {
            guard let index = chain.firstIndex(of: identity.size),
                  index + 1 < chain.count
            else { return nil }
            return ModelID(family: identity.family, size: chain[index + 1])
        }
        guard let ladder = accuracyLadders[identity.family],
              let index = ladder.firstIndex(of: identity), index > 0
        else { return nil }
        return ladder[index - 1]
    }
}
