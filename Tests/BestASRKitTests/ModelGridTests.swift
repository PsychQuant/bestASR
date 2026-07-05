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

    @Test func `Unverified rows carry no repo id to fabricate URLs from`() {
        // Spec scenario: unverified row guidance never prints a guessed URL.
        for row in ModelGrid.rows where !row.verified {
            #expect(row.hfRepo == nil, "\(row.modelId) is unverified but has a repo id")
        }
        // And verified priority-1 rows do have live-probed repos.
        let verified = ModelGrid.rows(backend: ModelGrid.backendMLXAudio, priorityCeiling: 1)
            .filter(\.verified)
        #expect(!verified.isEmpty)
        #expect(verified.allSatisfy { $0.hfRepo != nil })
    }

    @Test func `Model ids are unique across the whole grid — BCNF key discipline`() {
        let ids = ModelGrid.rows.map(\.modelId)
        #expect(Set(ids).count == ids.count)
    }

    @Test func `Existing backends' rows mirror the live-validated quantization table`() {
        let cppTiny = ModelGrid.rows.filter {
            $0.backend == ModelGrid.backendWhisperCpp && $0.size == "tiny"
        }
        #expect(Set(cppTiny.map(\.quantization)) == Set(["q5_1", "q8_0"]))
        let cppLarge = ModelGrid.rows.filter {
            $0.backend == ModelGrid.backendWhisperCpp && $0.size == "large-v3"
        }
        #expect(cppLarge.map(\.quantization) == ["q5_0"])
    }
}
