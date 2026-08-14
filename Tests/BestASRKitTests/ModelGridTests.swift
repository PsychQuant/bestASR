import Foundation
import Testing
@testable import BestASRKit

/// Task 2.1 (spec model-grid).
struct ModelGridTests {
    @Test func `Grid enumerates all 15 mlx-audio families and at least 30 total rows`() {
        // Spec scenario: grid completeness.
        #expect(ModelGrid.mlxFamilies.count == 15)
        #expect(ModelGrid.rows.count >= 30)
    }


    @Test func `Live and reference parakeet rows coexist distinguishably`() {
        // #35 (spec model-grid "Full-family catalog"): same family, different
        // backend id — the live row enumerates, the reference row never does.
        let parakeet = ModelGrid.rows.filter { $0.family == "parakeet" }
        #expect(parakeet.contains { $0.backend == ModelGrid.backendFluidParakeet })
        #expect(parakeet.contains { $0.backend == ModelGrid.backendMLXAudio })
        // Reference-catalog integrity: adding the live row changed nothing
        // in the 15-family reference section.
        let live = ModelGrid.rows(backend: ModelGrid.backendFluidParakeet, priorityCeiling: nil)
        #expect(!live.isEmpty)
        #expect(live.allSatisfy { $0.priority == 1 })
    }

    @Test func `Historical first-run tier is retained on the reference catalog`() {
        // #20: priority is historical metadata on reference rows.
        let p1 = ModelGrid.rows(backend: ModelGrid.backendMLXAudio, priorityCeiling: 1)
            .map(\.modelId)
        #expect(Set(p1) == Set([
            "mlx-audio|whisper|large-v3-turbo|unknown",
            "mlx-audio|parakeet|0.6b-v3|unknown",
            "mlx-audio|qwen3-asr|small|4bit",
            "mlx-audio|moonshine|base|unknown",
        ]))
    }

    @Test func `Verified reference rows keep their revision pins`() {
        // #15 pins survive the backend removal — reference value (#20).
        for row in ModelGrid.rows(backend: ModelGrid.backendMLXAudio, priorityCeiling: nil)
        where row.verified {
            #expect(row.hfRevision?.range(
                of: "^[0-9a-f]{40}$", options: .regularExpression) != nil)
        }
    }

    @Test func `Priority ceiling gates the default sweep and nil widens to all`() {
        // Spec scenario: default sweep / widening flag.
        let defaultSweep = ModelGrid.rows(backend: ModelGrid.backendMLXAudio)
        let widened = ModelGrid.rows(backend: ModelGrid.backendMLXAudio, priorityCeiling: nil)
        #expect(defaultSweep.allSatisfy { $0.priority == 1 })
        #expect(widened.count > defaultSweep.count)
        #expect(widened.contains { $0.priority == 3 })
    }

    @Test func `Repo ids are never guessed — a pinned revision proves the probe`() {
        // #20's intent, revised by #65: the grid must never print a GUESSED
        // URL. The proof of a real probe is the revision pin — any row
        // carrying hfRepo MUST carry hfRevision (probed, pinned, auditable);
        // `verified` stays a pure measurement flag (a probed-but-unmeasured
        // row is legal: repo pinned, verified false until benchmarked).
        for row in ModelGrid.rows where row.hfRepo != nil {
            #expect(
                row.hfRevision != nil || row.backend != ModelGrid.backendMLXAudio,
                "\(row.modelId) has a repo id without a revision pin")
        }
        // And verified priority-1 mlx rows do have live-probed repos.
        let verified = ModelGrid.rows(backend: ModelGrid.backendMLXAudio, priorityCeiling: 1)
            .filter(\.verified)
        #expect(!verified.isEmpty)
        #expect(verified.allSatisfy { $0.hfRepo != nil })
    }





    @Test func `No catalog row spells the removed placeholder`() {
        // The deferral this replaced is over: read-time canonicalisation
        // (`ModelGrid.canonical`) lets the catalog carry true values without
        // rewriting a stored key, so the placeholder is gone from the catalog
        // while every measurement taken under it still resolves.
        for row in ModelGrid.rows {
            #expect(row.quantization != .named(ModelID.removedPlaceholder), "\(row.modelId)")
        }
        // The SIZE axis has two rows left, and they are a CLOSED list: neither
        // upstream publishes a version name, so there is nothing true to put
        // there. Naming them keeps the gap visible; #187 decides between
        // dropping the rows, relaxing the spec, or waiting for upstream.
        let sizeGap = Set(
            ModelGrid.rows.filter { $0.size == ModelID.removedPlaceholder }.map(\.family))
        #expect(sizeGap == ["mega-asr", "qwen3-forcedaligner"])
    }

    @Test func `Model ids are unique across the whole grid — BCNF key discipline`() {
        let ids = ModelGrid.rows.map(\.modelId)
        #expect(Set(ids).count == ids.count)
    }

    @Test func `Existing backends' rows mirror the live-validated quantization table`() {
        let cppTiny = ModelGrid.rows.filter {
            $0.backend == ModelGrid.backendWhisperCpp && $0.size == "tiny"
        }
        #expect(Set(cppTiny.map(\.quantization.serialised)) == Set(["q5_1", "q8_0"]))
        let cppLarge = ModelGrid.rows.filter {
            $0.backend == ModelGrid.backendWhisperCpp && $0.size == "large-v3"
        }
        #expect(cppLarge.map(\.quantization.serialised) == ["q5_0"])
    }

    @Test func `An mlx identity resolves to the pinned row round-trip`() throws {
        // #65 verify F5: the address the runner emits (and projection
        // produces) must resolve back to the SAME pinned row — the persist
        // path depends on it (F1 regression lock).
        let canary = try #require(ModelID(family: "canary", size: "1b"))
        let row = try #require(ModelGrid.row(backend: ModelGrid.backendMLXAudio, identity: canary))
        #expect(row.identity == canary)
        #expect(row.hfRepo != nil)
        #expect(row.hfRevision != nil)
        // The persisted modelId built from the resolved row keeps the family.
        // The pin `Mediform/canary-1b-v2-mlx-q8` states the quantization the row
        // used to hide behind `default` (#183).
        #expect(row.modelId == "mlx-audio|canary|1b|q8")
    }

    @Test func `Two families sharing a size each resolve to their own row`() throws {
        // The collision the bare-size fallback used to settle by "first row
        // wins": canary 1b shadowed mms 1b, and nothing said so.
        let canary = try #require(ModelID(family: "canary", size: "1b"))
        let mms = try #require(ModelID(family: "mms", size: "1b"))
        let canaryRow = try #require(
            ModelGrid.row(backend: ModelGrid.backendMLXAudio, identity: canary))
        let mmsRow = try #require(
            ModelGrid.row(backend: ModelGrid.backendMLXAudio, identity: mms))

        #expect(canaryRow.identity == canary)
        #expect(mmsRow.identity == mms)
        #expect(canaryRow.identity != mmsRow.identity)
        #expect(canaryRow.modelId != mmsRow.modelId)
    }

    @Test func `A bare size naming two families resolves to neither`() throws {
        // The ambiguity is now reported rather than settled. `matching` still
        // returns both rows — a caller that wants to list them can — but the
        // single-identity resolution refuses to choose.
        let ambiguous = ModelGrid.rows(backend: ModelGrid.backendMLXAudio, matching: "1b")
        #expect(Set(ambiguous.map(\.identity)).count == 2)
        // And it SAYS which two, rather than only that it refused. Round 8's
        // verify named this: a caller handed a bare `nil` inherits a position
        // on ambiguity it never took.
        let resolution = ModelGrid.identity(backend: ModelGrid.backendMLXAudio, matching: "1b")
        guard case .ambiguous(let named) = resolution else {
            Issue.record("'1b' resolved to \(resolution), not to the two models that publish it")
            return
        }
        #expect(named.map(ModelGrid.address(for:)) == ["canary/1b", "mms/1b"])

        // An unambiguous bare size still resolves, so whisper-style backends
        // keep addressing rows the way their users type them.
        #expect(ModelGrid.identity(backend: ModelGrid.backendWhisperCpp, matching: "tiny")
                == .resolved(try #require(ModelID(family: "whisper", size: "tiny"))))
    }
}

/// Task 2.2 residue found during verify round 1 (#183): the benchmark WRITER
/// and the projection READER were addressing models by two different rules
/// that happen to agree on today's catalog.
struct ModelAddressingTests {
    @Test func `Every catalog row addresses canonically, and resolves back`() throws {
        // The address no longer asks which runtime is hosting. Round 6 showed
        // why the previous rule failed #183's third EXPECTED: under whisperkit
        // `base` meant whisper/base, under mlx-audio it meant moonshine/base,
        // and both addressed as the bare `base` because each was unambiguous
        // *within its own runtime*. Keeping the model string and changing
        // --backend silently changed the model.
        for row in ModelGrid.rows {
            let address = ModelGrid.address(for: row.identity)
            #expect(address == "\(row.family)/\(row.size)")
            #expect(ModelGrid.identity(backend: row.backend, matching: address)
                    == .resolved(row.identity),
                    "\(row.modelId) addressed as '\(address)' does not resolve back")
        }
    }

    @Test func `One address means one model in every runtime`() throws {
        // The concrete case round 6 found. Both rows exist; `base` used to
        // address both.
        let whisperBase = try #require(ModelID(family: "whisper", size: "base"))
        let moonshineBase = try #require(ModelID(family: "moonshine", size: "base"))
        #expect(ModelGrid.address(for: whisperBase) == "whisper/base")
        #expect(ModelGrid.address(for: moonshineBase) == "moonshine/base")
        #expect(ModelGrid.address(for: whisperBase) != ModelGrid.address(for: moonshineBase))

        // And an address resolves to the same model no matter which runtime
        // is asked — when that runtime hosts it at all.
        for backend in [ModelGrid.backendWhisperKit, ModelGrid.backendWhisperCpp] {
            #expect(ModelGrid.identity(backend: backend, matching: "whisper/base")
                    == .resolved(whisperBase))
        }
    }

    @Test func `A size shared by two families keeps the family in its address`() throws {
        let canary = try #require(ModelID(family: "canary", size: "1b"))
        let mms = try #require(ModelID(family: "mms", size: "1b"))
        #expect(ModelGrid.address(for: canary) == "canary/1b")
        #expect(ModelGrid.address(for: mms) == "mms/1b")
    }
}
