import Foundation
import Testing

@testable import BestASRKit

/// Round-4 verify findings C4 and C5 (#183).
struct IdentityValidationTests {

    // MARK: - C4a: the only initialiser was not the only way in

    @Test func `Decoding refuses an identity the initialiser would refuse`() {
        // `ModelID` documented its failable init as "the only way to build
        // one"; the synthesized Decodable wrote the stored properties
        // directly, so a JSON payload walked straight past it. Reachable from
        // outside, not theoretical: `BenchmarkRecord.identity` is a public
        // Codable field.
        for payload in [
            #"{"family":"","size":"small"}"#,
            #"{"family":"whisper","size":""}"#,
            #"{"family":"whisper ","size":"small"}"#,
            #"{"family":"whisper","size":" small"}"#,
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(ModelID.self, from: Data(payload.utf8))
            }
        }
        // A well-formed one still decodes.
        #expect(throws: Never.self) {
            try JSONDecoder().decode(
                ModelID.self, from: Data(#"{"family":"whisper","size":"small"}"#.utf8))
        }
    }

    // MARK: - C4c: the separators its own grammar parses on

    @Test func `A component may not carry the store key or address separator`() {
        // `model_id` is joined on `|` and an address on `/`. A component
        // carrying either produces a key that parses back into different
        // segments than it was built from — silent corruption of the one
        // string this whole change makes load-bearing.
        #expect(ModelID(family: "whis|per", size: "small") == nil)
        #expect(ModelID(family: "whisper", size: "sm|all") == nil)
        #expect(ModelID(family: "whis/per", size: "small") == nil)
        #expect(ModelID(family: "whisper", size: "sm/all") == nil)
        #expect(Quantization(named: "q5|1") == nil)
        #expect(Quantization(named: "q5/1") == nil)
        // The reserved deferred spellings contain `:`, which is fine.
        #expect(ModelID(family: "whisper", size: "large-v3-turbo") != nil)
        #expect(Quantization(named: "q5_1") != nil)
    }

    @Test func `A malformed named value is not a comparable quantization`() {
        // `Quantization.named` is a public case, so `init(named:)`'s refusals
        // can be walked past. Rather than wrap the payload — 35 call sites for
        // a round trip that already fails CLOSED in every case tested — the
        // gate that matters refuses to vouch for a malformed value, and the
        // catalog test below refuses to ship one.
        #expect(Quantization.named("").isComplete == false)
        #expect(Quantization.named("   ").isComplete == false)
        #expect(Quantization.named("q5|1").isComplete == false)
        #expect(Quantization.named("q5_1").isComplete)
    }


    // MARK: - C5: the headline fix never reached a user

    @Test func `A locked backend resolves a bare size in ITS catalog, not whisper's`() throws {
        // proposal.md leads with this defect: sensevoice small was charged
        // whisper small's 2.5 GB. The type-level fix landed; the user-facing
        // path did not, because the override resolved through a whisper-first
        // rule before the backend was consulted. On a ~2 GB machine that
        // turned a runnable model into "model 'base' is not available on
        // backend fluid-sensevoice".
        let host = SystemInfo(
            chip: "Apple M2", unifiedMemoryGB: 2.0, hasANE: true, macosVersion: "27.0")
        let rec = try Router.recommend(
            host: host, profile: .medium, requestedLanguage: nil,
            backendOverride: "fluid-sensevoice", modelOverride: "small",
            records: [], availability: [.fluidSenseVoice: true])

        #expect(rec.backend == .fluidSenseVoice)
        // The ADDRESS, which is what makes the claim: `small` alone is also
        // whisper small, and that collision is the defect this test guards.
        #expect(rec.model == "sensevoice/small")
    }

    @Test func `An unlocked bare size still means whisper`() throws {
        // The whisper-first rule is right when nobody named a backend — it is
        // what `--model small` has always meant. Only the locked case was wrong.
        let identity = try #require(ModelRegistry.liveIdentity(named: "small"))
        #expect(identity.family == "whisper")
    }
}

/// Round-5 verify (#183, DA + codex, same root cause): the downgrade walk is
/// runtime-blind, so it can hand back a model the chosen runtime does not host.
struct DowngradeStaysInsideItsRuntimeTests {
    @Test func `A downgrade never proposes a model the runtime does not host`() throws {
        // fluid-parakeet hosts exactly one row (0.6b-v3, 2.0 GB). The parakeet
        // ladder is built across ALL backends, so on a machine too small for
        // 2.0 GB the walk previously stepped to `parakeet 0.6b` — which only
        // mlx-audio has. `--backend fluid-parakeet` would then name a model
        // fluid-parakeet cannot run.
        //
        // This is a regression THIS change introduced: before it, nextSmaller
        // took a String and consulted the whisper-only downgradeChain, so a
        // non-whisper name fell out immediately and no downgrade happened.
        let identity = try #require(ModelID(family: "parakeet", size: "0.6b-v3"))
        let host = SystemInfo(
            chip: "Apple M1", unifiedMemoryGB: 1.7, hasANE: true, macosVersion: "27.0")

        let rec = try Router.recommend(
            host: host, profile: .medium, requestedLanguage: nil,
            backendOverride: "fluid-parakeet", modelOverride: "0.6b-v3",
            records: [], availability: [.fluidParakeet: true])

        #expect(rec.backend == .fluidParakeet)
        let hosted = Set(
            ModelGrid.rows(backend: ModelGrid.backendFluidParakeet, priorityCeiling: nil)
                .map { ModelGrid.address(for: $0.identity) })
        #expect(hosted.contains(rec.model),
                "recommended '\(rec.model)' which fluid-parakeet does not host (\(hosted))")
        _ = identity
    }

    @Test func `Within one runtime the whisper chain still steps`() throws {
        // The fix must not disable downgrading where it is correct.
        let large = try #require(ModelID(family: "whisper", size: "large-v3"))
        let next = try #require(
            ModelRegistry.nextSmaller(than: large, hostedBy: ModelGrid.backendWhisperKit))
        #expect(next == ModelID(family: "whisper", size: "medium"))
    }
}
