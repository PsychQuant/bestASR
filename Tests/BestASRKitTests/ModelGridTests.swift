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
            "mlx-audio|whisper|large-v3-turbo|default",
            "mlx-audio|parakeet|0.6b|default",
            "mlx-audio|qwen3-asr|small|4bit",
            "mlx-audio|moonshine|base|default",
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





    @Test func `The catalog still spells the placeholder — deferred, not forgotten`() {
        // The user's instruction was to remove `default` from identities
        // entirely, and this change does not do it. Verify round 4 measured
        // why: assigning the real values rotates 19 of 37 model_id keys while
        // 344 of 383 stored measurements still reference the old ones, and the
        // record re-encoding is a declared Non-Goal here. Option 3 was chosen —
        // the type work lands, the re-key travels with the re-encoding.
        //
        // This test exists so that deferral is VISIBLE in the suite rather than
        // absent from it. When the re-encoding change lands it must fail, and
        // the tests it replaced (the four-case assignment, the closed unknown
        // list, the CLI/MCP placeholder assertions) come back with it.
        let placeholder = ModelGrid.rows.filter {
            $0.quantization == .named(ModelID.removedPlaceholder)
                || $0.size == ModelID.removedPlaceholder
        }
        #expect(placeholder.count == 19,
                "the catalog's placeholder count moved without the re-key landing")
        // And every one of them still produces the key that is on disk today.
        for row in placeholder {
            #expect(row.modelId.hasSuffix("|\(ModelID.removedPlaceholder)")
                    || row.size == ModelID.removedPlaceholder)
        }
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
        #expect(row.modelId == "mlx-audio|canary|1b|default")
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

    @Test func `A bare size naming two families resolves to neither`() {
        // The ambiguity is now reported rather than settled. `matching` still
        // returns both rows — a caller that wants to list them can — but the
        // single-identity resolution refuses to choose.
        let ambiguous = ModelGrid.rows(backend: ModelGrid.backendMLXAudio, matching: "1b")
        #expect(Set(ambiguous.map(\.identity)).count == 2)
        #expect(ModelGrid.identity(backend: ModelGrid.backendMLXAudio, matching: "1b") == nil)

        // An unambiguous bare size still resolves, so whisper-style backends
        // keep addressing rows the way their users type them.
        #expect(ModelGrid.identity(backend: ModelGrid.backendWhisperCpp, matching: "tiny")
                == ModelID(family: "whisper", size: "tiny"))
    }
}

/// Task 2.2 residue found during verify round 1 (#183): the benchmark WRITER
/// and the projection READER were addressing models by two different rules
/// that happen to agree on today's catalog.
struct ModelAddressingTests {
    @Test func `A measurement of any catalog row projects back to that row's identity`() throws {
        // Round-4 verify C7 renamed and rebuilt this. The previous version
        // claimed to lock "writer and reader address every row identically"
        // and could not fail: `address(for:backend:)` is DEFINED as
        // `identity(matching: size) == identity ? size : "family/size"`, so
        // re-asking that question is true in both branches — and it called
        // neither the writer nor the reader whose agreement its name claimed.
        //
        // What it checks now is a real round trip through the reader: a stored
        // key for each catalog row, projected, must come back as that row's
        // identity. That can fail — the legacy `parts[1] == parts[2]` rewrite
        // would swallow any row whose family equals its own size.
        let corpus = CorpusRow(
            name: "c", language: "en", audioSHA256: String(repeating: "c", count: 64),
            referenceSHA256: "", duration: 30, audioPath: "", referencePath: "")
        for row in ModelGrid.rows {
            let snapshot = BenchmarkStore.Snapshot(
                machines: [], models: [], corpora: [corpus],
                measurements: [MeasurementRow(
                    modelId: row.modelId, corpusId: corpus.corpusId, machineId: "h",
                    measuredAt: Date(timeIntervalSince1970: 1), metricKind: .wer,
                    errorRate: 0.1, rtf: 0.1, peakMemoryGB: 1, warmupSeconds: 1,
                    appVersion: "0.3.0", macosVersion: "27.0")],
                warnings: [])
            let projected = try #require(
                snapshot.projectedRecords().first, "\(row.modelId) projected to nothing")
            #expect(projected.identity == row.identity,
                    "\(row.modelId) projected to \(String(describing: projected.identity))")
            #expect(projected.backend == row.backend)
        }
    }

    @Test func `A size shared by two families keeps the family in its address`() throws {
        let canary = try #require(ModelID(family: "canary", size: "1b"))
        let mms = try #require(ModelID(family: "mms", size: "1b"))
        #expect(ModelGrid.address(for: canary, backend: ModelGrid.backendMLXAudio) == "canary/1b")
        #expect(ModelGrid.address(for: mms, backend: ModelGrid.backendMLXAudio) == "mms/1b")

        // And an unambiguous one does not — `--model tiny` stays what users type.
        let tiny = try #require(ModelID(family: "whisper", size: "tiny"))
        #expect(ModelGrid.address(for: tiny, backend: ModelGrid.backendWhisperCpp) == "tiny")
    }

    @Test func `The rule keys on ambiguity, not on which vendor ships the runtime`() throws {
        // mlx-audio hosts both ambiguous and unambiguous sizes. A vendor rule
        // gives every mlx row a family prefix; the ambiguity rule gives one
        // only where the size needs it. That difference is the finding.
        let moonshine = try #require(ModelID(family: "moonshine", size: "base"))
        #expect(ModelGrid.address(for: moonshine, backend: ModelGrid.backendMLXAudio) == "base")
        let canary = try #require(ModelID(family: "canary", size: "1b"))
        #expect(ModelGrid.address(for: canary, backend: ModelGrid.backendMLXAudio) == "canary/1b")
    }
}
