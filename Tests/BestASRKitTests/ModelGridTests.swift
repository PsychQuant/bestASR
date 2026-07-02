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

    @Test func `First-run set matches the spec example`() {
        // Spec Example: the four priority-1 mlx-audio model ids.
        let p1 = ModelGrid.rows(backend: ModelGrid.backendMLXAudio, priorityCeiling: 1)
            .map(\.modelId)
        #expect(Set(p1) == Set([
            "mlx-audio|whisper|large-v3-turbo|4bit",
            "mlx-audio|parakeet|0.6b|default",
            "mlx-audio|qwen3-asr|small|4bit",
            "mlx-audio|moonshine|base|default",
        ]))
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
