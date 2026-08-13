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

    @Test func `The same parakeet under two runtimes is one identity`() throws {
        // D3: the two rows pin the same upstream model —
        // FluidInference/parakeet-tdt-0.6b-v3-coreml and
        // mlx-community/parakeet-tdt-0.6b-v3 — so a size of `0.6b` on one of
        // them made one model look like two, which is exactly what this
        // change exists to end. Size is the version the pin resolves to, not
        // the catalog author's abbreviation.
        let fluid = try #require(
            ModelGrid.rows.first { $0.backend == ModelGrid.backendFluidParakeet })
        let mlx = try #require(
            ModelGrid.rows.first {
                $0.backend == ModelGrid.backendMLXAudio && $0.family == "parakeet"
            })
        #expect(fluid.identity == mlx.identity)
        #expect(fluid.identity.size == "0.6b-v3")
        // Same model, different runtime: the rows stay distinguishable.
        #expect(fluid.backend != mlx.backend)
        #expect(fluid.modelId != mlx.modelId)
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

    @Test func `No catalog row states the removed placeholder as its quantization`() {
        // #183: `default` stood for seven different facts across 19 of the 37
        // rows. Each is now one of the four cases, so the word means nothing
        // here any more.
        for row in ModelGrid.rows {
            #expect(row.quantization != .named(ModelID.removedPlaceholder),
                    "\(row.modelId) still carries the placeholder")
        }
    }

    @Test func `Only the rows whose quantization nobody recorded are unknown`() {
        // A CLOSED list, and it may not be extended by resemblance: a new row
        // is unknown only if this test is edited to say so, deliberately.
        // Six mlx-audio reference rows qualify — four pin a repo that does not
        // state its precision (moonshine, nemotron-asr, parakeet, whisper) and
        // two pin nothing at all (distil-whisper, mms). None is reachable as a
        // benchmark candidate; the backend is not bundled.
        let expected: Set<String> = [
            "mlx-audio|moonshine|base|unknown",
            "mlx-audio|nemotron-asr|streaming|unknown",
            "mlx-audio|parakeet|0.6b-v3|unknown",
            "mlx-audio|whisper|large-v3-turbo|unknown",
            "mlx-audio|distil-whisper|large-v3|unknown",
            "mlx-audio|mms|1b|unknown",
            // Neither upstream publishes a size either — the open item this
            // change did not close (see tasks 2.4).
            "mlx-audio|mega-asr|default|unknown",
            "mlx-audio|qwen3-forcedaligner|default|unknown",
        ]
        let actual = Set(
            ModelGrid.rows.filter { $0.quantization == .unknown }.map(\.modelId))
        #expect(actual == expected)
    }

    @Test func `Each runtime states its quantization in the kind that fits it`() {
        // apple-speech has no quantization axis at all; WhisperKit picks its
        // own bundle from 27 published variants; the fluid runtimes now state
        // the precision they load (task 5.1), so a dependency bump cannot
        // change it silently.
        let apple = ModelGrid.rows.filter { $0.backend == ModelGrid.backendAppleSpeech }
        #expect(!apple.isEmpty)
        #expect(apple.allSatisfy { $0.quantization == .notApplicable })

        let whisperKit = ModelGrid.rows.filter { $0.backend == ModelGrid.backendWhisperKit }
        #expect(whisperKit.count == 6)
        #expect(whisperKit.allSatisfy { $0.quantization == .deferred(.runtime) })

        let fluid = ModelGrid.rows.filter {
            [ModelGrid.backendFluidParakeet, ModelGrid.backendFluidParaformer,
             ModelGrid.backendFluidSenseVoice].contains($0.backend)
        }
        #expect(fluid.count == 3)
        for row in fluid {
            guard case .named = row.quantization else {
                Issue.record("\(row.modelId) defers to FluidAudio instead of stating a precision")
                continue
            }
        }
        // The values are FluidAudio's own defaults, stated — not chosen. Any
        // other value would have retired the measurements already in the store.
        #expect(ModelGrid.rows.first { $0.backend == ModelGrid.backendFluidParakeet }?
                .quantization == .named("int8"))
        #expect(ModelGrid.rows.first { $0.backend == ModelGrid.backendFluidSenseVoice }?
                .quantization == .named("fp16"))
        #expect(ModelGrid.rows.first { $0.backend == ModelGrid.backendFluidParaformer }?
                .quantization == .named("fp16"))
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
