import Foundation
import Testing

@testable import BestASRKit

/// Task 1.1 / 1.2 of change `model-identity-structured` (issue #183).
///
/// The audit lens drove four of these cases. `Quantization` serialises to the
/// same flat string the store already uses, so a `named` value that happens to
/// spell a reserved word would decode as a different case — a silent identity
/// change. The constructors refuse those spellings rather than letting the
/// round-trip lose information, and there is no unchecked initialiser to route
/// around them.
struct ModelIDTests {

    // MARK: - 1.1 ModelID

    @Test func `two identities with the same family and size are equal and hash alike`() throws {
        let a = try #require(ModelID(family: "whisper", size: "large-v3-turbo"))
        let b = try #require(ModelID(family: "whisper", size: "large-v3-turbo"))
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(Set([a, b]).count == 1)
    }

    @Test func `family and size are both part of the identity`() throws {
        let whisperSmall = try #require(ModelID(family: "whisper", size: "small"))
        let senseVoiceSmall = try #require(ModelID(family: "sensevoice", size: "small"))
        // The collision this change exists to end: two families sharing a size
        // name are two models, not one.
        #expect(whisperSmall != senseVoiceSmall)
        #expect(Set([whisperSmall, senseVoiceSmall]).count == 2)
    }

    @Test func `an empty family or size is refused`() {
        #expect(ModelID(family: "", size: "small") == nil)
        #expect(ModelID(family: "whisper", size: "") == nil)
        #expect(ModelID(family: "", size: "") == nil)
        #expect(ModelID(family: "   ", size: "small") == nil)
        #expect(ModelID(family: "whisper", size: "small") != nil)
    }

    @Test func `a component carrying surrounding whitespace is refused`() {
        // Lazy lens: a component read from a column with a stray space. Two
        // spellings of one model is the defect class this change ends, so the
        // malformed value is refused rather than silently trimmed.
        #expect(ModelID(family: "whisper ", size: "small") == nil)
        #expect(ModelID(family: "whisper", size: " small") == nil)
        #expect(ModelID(family: "whisper\n", size: "small") == nil)
    }

    @Test func `a historical component spelling the placeholder stays readable`() throws {
        // Two of the 37 registered rows record `default` as their size, and
        // `StoreProjection` builds a `ModelID` from exactly those four stored
        // segments. Refusing the spelling here would make those records
        // unreadable — the opposite of what benchmark-store requires. `default`
        // is a catalog-content defect, not a syntactic one: the rule that no
        // *row* may carry it belongs to the catalog test, not to this type.
        let historical = try #require(
            ModelID(family: "mega-asr", size: ModelID.removedPlaceholder))
        #expect(historical.size == ModelID.removedPlaceholder)
        #expect(try #require(ModelID(family: ModelID.removedPlaceholder, size: "small"))
                .family == ModelID.removedPlaceholder)
    }

    @Test func `a ModelID round-trips through Codable`() throws {
        let original = try #require(ModelID(family: "parakeet", size: "0.6b-v3"))
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ModelID.self, from: data) == original)
    }

    // MARK: - 1.2 Quantization

    @Test func `a named quantization encodes to its own value`() throws {
        for value in ["q5_1", "q8_0", "4bit", "q8"] {
            let q = try #require(Quantization(named: value))
            #expect(q.serialised == value)
            #expect(Quantization(serialised: value) == q)
        }
    }

    @Test func `the three non-named cases each have a distinct reserved spelling`() {
        let cases: [Quantization] = [
            .notApplicable, .deferred(.runtime), .deferred(.dependency), .unknown,
        ]
        let spellings = cases.map(\.serialised)
        #expect(Set(spellings).count == cases.count)
        for (q, spelling) in zip(cases, spellings) {
            #expect(Quantization(serialised: spelling) == q)
        }
    }

    @Test func `deferred and unknown do not decode to each other`() {
        // They mean different things: `deferred` is a value somebody else picks
        // and can change under us; `unknown` is a gap in the record.
        #expect(Quantization.deferred(.runtime) != Quantization.unknown)
        #expect(Quantization.deferred(.dependency) != Quantization.deferred(.runtime))
        #expect(Quantization(serialised: Quantization.unknown.serialised) != .deferred(.runtime))
    }

    @Test func `only unknown is an incomplete identity`() {
        #expect(Quantization.unknown.isComplete == false)
        #expect(Quantization.notApplicable.isComplete)
        #expect(Quantization.deferred(.runtime).isComplete)
        #expect(Quantization.deferred(.dependency).isComplete)
        #expect(Quantization.named("q8").isComplete)
    }

    @Test func `every case round-trips through Codable`() throws {
        for q in [Quantization.notApplicable, .deferred(.runtime), .deferred(.dependency),
                  .unknown, try #require(Quantization(named: "q5_1"))] {
            let data = try JSONEncoder().encode(q)
            #expect(try JSONDecoder().decode(Quantization.self, from: data) == q)
        }
    }

    @Test func `a named value may not spell a reserved word`() {
        // Scoundrel lens: `named("unknown")` would encode to the reserved
        // spelling and decode back as `.unknown` — a silent case change.
        for reserved in [Quantization.notApplicable, .deferred(.runtime),
                         .deferred(.dependency), .unknown].map(\.serialised) {
            #expect(Quantization(named: reserved) == nil)
        }
    }

    @Test func `a named value may not be empty, padded, or the removed placeholder`() {
        #expect(Quantization(named: "") == nil)
        #expect(Quantization(named: "   ") == nil)
        #expect(Quantization(named: " q8 ") == nil)
        #expect(Quantization(named: ModelID.removedPlaceholder) == nil)
    }

    @Test func `the legacy placeholder still decodes, and stays visibly wrong`() {
        // 337 stored records spell their quantization `default`. Decoding must
        // not reinterpret them — a record that is wrong should read as wrong,
        // which is what lets the migration find it.
        #expect(Quantization(serialised: ModelID.removedPlaceholder)
                == .named(ModelID.removedPlaceholder))
    }
}
