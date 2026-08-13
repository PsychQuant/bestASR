import Foundation

/// Which model — as a value, not as a formatted string (#183).
///
/// The store has always keyed models by `backend|family|size|quantization`
/// (`ModelRow.id`), but the lookup path took a string whose grammar depended on
/// the backend: mlx-audio addressed rows `family/size`, every other backend by
/// bare `size`. Three defects followed, each patched separately and each still
/// visible in the source: a bare-size lookup that resolved to "first row wins"
/// when two families shared a size name (#65), a memory table that had to
/// reconcile those colliding names with `max` (#50), and a projection that
/// discarded the family segment to fit the address grammar back down.
///
/// Making the identity a value ends all three at once: the family is no longer
/// something a caller can forget to carry.
public struct ModelID: Hashable, Codable, Sendable {
    /// The model family — `whisper`, `parakeet`, `sensevoice`, …
    public let family: String
    /// The version within that family — `large-v3-turbo`, `0.6b-v3`, `small`, …
    ///
    /// Where a catalog row pins an upstream repository, this SHALL be the
    /// version that pin resolves to, not an abbreviation of it. Both parakeet
    /// rows pin `parakeet-tdt-0.6b-v3`; recording one as `0.6b` made the same
    /// model look like two.
    public let size: String

    /// The only way to build one — `nil` when either component is unusable.
    ///
    /// There is deliberately no unchecked initialiser. `BestASRKit` is a single
    /// module, so an `internal` escape hatch would protect nothing: the caller
    /// most likely to reach for the shorter spelling is inside the module.
    /// Callers holding compile-time literals (the catalog) unwrap once, loudly.
    ///
    /// Two rejections, and both describe the same failure — an identity that
    /// would not identify:
    ///
    /// - **Empty or blank.** An absent family is precisely what this type
    ///   exists to make impossible to carry around unnoticed.
    /// - **Surrounding whitespace.** `"whisper "` and `"whisper"` would be two
    ///   identities for one model, which is the defect class this change ends
    ///   (#65, #50). Trimming silently would be a mutation, not a validation,
    ///   so the malformed component is refused instead.
    ///
    /// ``removedPlaceholder`` is deliberately **not** among them. `default` is
    /// a defect in a catalog row's *content*, not in the syntax of a component,
    /// and two stored records spell their size that way. `StoreProjection`
    /// builds an identity from exactly those stored segments, so refusing the
    /// spelling here would make history unreadable — which benchmark-store
    /// forbids. The rule that no *row* may carry it is enforced where rows are
    /// defined, by the catalog test.
    public init?(family: String, size: String) {
        guard identifying(family), identifying(size) else { return nil }
        self.family = family
        self.size = size
    }

    /// The placeholder this change removes from every identity (#183).
    ///
    /// Defined once so the catalog test that asserts its absence and the
    /// constructors that refuse it cannot disagree about its spelling. It
    /// stood for seven different facts across 19 of the 37 registered rows;
    /// `docs/model-identity-audit.csv` records which row meant which.
    public static let removedPlaceholder = "default"
}

/// Whether a string can serve as part of an identity.
///
/// Shared by ``ModelID`` and ``Quantization`` so the two halves of a `model_id`
/// cannot drift into different notions of a well-formed component. Three ways
/// to fail:
///
/// - **Absent** — empty says nothing.
/// - **Whitespace-padded** — `"whisper "` and `"whisper"` would be two
///   identities for one model, the defect class this change ends (#65, #50).
/// - **Carrying `|` or `/`** — the separators this project's own two
///   serialisations parse on: `model_id` is joined with `|`, an address with
///   `/`. A component containing one produces a string that splits back into
///   different segments than it was built from, which corrupts the single
///   string this whole change makes load-bearing (round-4 verify C4).
private func identifying(_ value: String) -> Bool {
    !value.isEmpty
        && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        && !value.contains("|") && !value.contains("/")
}

extension ModelID {
    // The failable init is documented as the only way to build one. It was
    // not: the synthesized `Decodable` wrote the stored properties directly,
    // so a JSON payload walked straight past every refusal (round-4 verify
    // C4). `BenchmarkRecord.identity` is a public Codable field, so that path
    // was reachable from outside the module, not merely theoretical.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let family = try container.decode(String.self, forKey: .family)
        let size = try container.decode(String.self, forKey: .size)
        guard let identity = ModelID(family: family, size: size) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath,
                      debugDescription:
                        "not a model identity: family \"\(family)\", size \"\(size)\""))
        }
        self = identity
    }
}

extension ModelID: CustomStringConvertible {
    /// For a human: `whisper large-v3-turbo`. The hosting runtime is not part of
    /// the identity, so it is not part of this rendering — callers that want
    /// `family size (runtime)` add the runtime themselves.
    public var description: String { "\(family) \(size)" }
}

/// The quantization of a catalog row, as a closed set of four distinguishable
/// facts rather than one word standing for all of them (#183).
///
/// An audit of the 37 registered rows found the literal `"default"` carrying
/// seven different meanings, which collapse into these four cases. The
/// distinction that matters most is ``deferred(_:)`` versus ``unknown``: a
/// deferred value is one somebody else picks and **can change under us** — the
/// Chinese-family engine used to call `ParaformerManager.load()` with no
/// precision while FluidAudio ships `ParakeetEncoderPrecision{int8, int4}`, so
/// a dependency bump could change what was measured without changing the
/// recorded identity. `unknown` is merely a gap in the record. Writing both as
/// `"default"` hid which one could drift.
public enum Quantization: Hashable, Codable, Sendable {
    /// This runtime has no quantization dimension (an OS-bundled model).
    case notApplicable
    /// A real value: `q5_1`, `q8_0`, `4bit`, …
    case named(String)
    /// Chosen by someone other than this project, and named so.
    case deferred(Deferrer)
    /// Nobody knows. A row in this state SHALL be excluded from comparison.
    case unknown

    /// Who decides a ``deferred(_:)`` value.
    public enum Deferrer: String, Hashable, Codable, Sendable {
        /// The backend's own runtime resolves it (WhisperKit fetches its own
        /// bundle from among 27 published variants).
        case runtime
        /// A third-party package's default resolves it, and may change on a
        /// version bump.
        case dependency
    }

    /// The spellings the three valueless cases occupy in the flat store key.
    ///
    /// Each contains a character (`/` or `:`) that no upstream quantization
    /// name uses, so a real value cannot collide with one by accident — and
    /// ``init(named:)`` refuses the collision on purpose anyway.
    private static let notApplicableSpelling = "n/a"
    private static let unknownSpelling = "unknown"
    private static func deferredSpelling(_ by: Deferrer) -> String { "deferred:\(by.rawValue)" }

    /// The value this case occupies in `model_id`'s fourth segment.
    public var serialised: String {
        switch self {
        case .notApplicable: return Self.notApplicableSpelling
        case .named(let value): return value
        case .deferred(let by): return Self.deferredSpelling(by)
        case .unknown: return Self.unknownSpelling
        }
    }

    /// Parse the fourth segment of a `model_id`.
    ///
    /// Anything that is not a reserved spelling is a named value — including
    /// the legacy `"default"`, which decodes as `.named("default")` rather than
    /// being silently reinterpreted. Old records stay readable and stay
    /// visibly wrong, which is what lets the migration find them.
    public init(serialised: String) {
        switch serialised {
        case Self.notApplicableSpelling: self = .notApplicable
        case Self.unknownSpelling: self = .unknown
        case Self.deferredSpelling(.runtime): self = .deferred(.runtime)
        case Self.deferredSpelling(.dependency): self = .deferred(.dependency)
        default: self = .named(serialised)
        }
    }

    /// A named value, or `nil` when the spelling is one this type cannot carry.
    ///
    /// Three refusals, one per adversary lens:
    ///
    /// - **A reserved spelling.** `named("unknown")` would serialise to the
    ///   reserved word and parse back as `.unknown` — the round trip would
    ///   silently change the case. Refusing is cheaper than a lossy encoding.
    /// - **Empty, blank, or whitespace-padded.** Same rule as a ``ModelID``
    ///   component: absent, or two spellings of one value.
    /// - **`"default"`.** The placeholder this change removes. Accepting it as
    ///   a *named* value would reintroduce it wearing a new hat.
    public init?(named value: String) {
        guard identifying(value), value != ModelID.removedPlaceholder else { return nil }
        let reserved = [
            Self.notApplicableSpelling, Self.unknownSpelling,
            Self.deferredSpelling(.runtime), Self.deferredSpelling(.dependency),
        ]
        guard !reserved.contains(value) else { return nil }
        self = .named(value)
    }

    /// Whether this value identifies the artifact well enough to compare it
    /// against another measurement.
    ///
    /// `deferred` counts as complete: the value is determinate at the moment of
    /// the run even though this project did not pick it. `unknown` does not.
    ///
    /// Neither does the legacy ``ModelID/removedPlaceholder``, and the two acts
    /// that separates are worth naming: ``init(serialised:)`` **preserves** it
    /// verbatim so the migration can find the records that carry it, while this
    /// property declines to **vouch** for it. 35 of the 383 stored measurements
    /// spell their quantization that way; marking them comparable would let a
    /// record that never said which artifact it measured rank against one that
    /// did.
    public var isComplete: Bool {
        switch self {
        case .unknown: return false
        // `named` is a public case, so `init(named:)`'s refusals can be walked
        // past (round-4 verify C4). Wrapping the payload would touch 35 call
        // sites for a round trip that already fails CLOSED in every case —
        // `named("unknown")` decodes back as `.unknown`, and the placeholder
        // is refused right here. So the gate that actually matters asks the
        // constructor's own question instead: a value this type would not
        // accept is not one it will vouch for.
        case .named(let value): return Quantization(named: value) != nil
        case .notApplicable, .deferred: return true
        }
    }
}

extension Quantization {
    // Codable through the same flat spelling the store uses, so the enum adds
    // no second serialisation format to keep in step with the first.
    public init(from decoder: any Decoder) throws {
        self.init(serialised: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(serialised)
    }
}
