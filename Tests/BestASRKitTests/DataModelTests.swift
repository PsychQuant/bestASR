import Foundation
import Testing
@testable import BestASRKit

struct DataModelTests {
    @Test func `SystemInfo carries the Apple hardware profile fields`() {
        let info = Fixtures.m5Max
        #expect(info.chip == "Apple M5 Max")
        #expect(info.unifiedMemoryGB > 0)
        #expect(info.hasANE == true)
        #expect(!info.macosVersion.isEmpty)
    }

    @Test func `ANE availability supports the unknown state`() {
        let info = SystemInfo(chip: "Apple M99", unifiedMemoryGB: 8, hasANE: nil, macosVersion: "27.0")
        #expect(info.hasANE == nil)
    }

    @Test func `TranscribeOptions carries model, quantization, language, and prompt`() {
        let options = TranscribeOptions(
            model: "small", quantization: "q5_0", language: "zh", prompt: "鄭澈, CoreML")
        #expect(options.model == "small")
        #expect(options.quantization == "q5_0")
        #expect(options.language == "zh")
        #expect(options.prompt == "鄭澈, CoreML")
        // Absent prompt defaults to nil (spec: adds nothing to the invocation).
        #expect(TranscribeOptions(model: "tiny", quantization: "default").prompt == nil)
    }

    @Test func `TranscriptSegment confidence is optional`() {
        let seg = TranscriptSegment(id: 1, start: 0, end: 1, text: "hi")
        #expect(seg.confidence == nil)
    }

    @Test func `BenchmarkRecord round-trips through Codable`() throws {
        let record = Fixtures.record()
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(BenchmarkRecord.self, from: data)
        #expect(decoded == record)
    }

    @Test func `timesRealtime inverts RTF and guards zero`() {
        #expect(Fixtures.record(timesRealtime: 12).timesRealtime == 12.0)
        let degenerate = BenchmarkRecord(
            backend: "whisperkit", model: "tiny", quantization: "default", language: "en",
            metricKind: .wer, errorRate: 0.1, rtf: 0, peakMemoryGB: 1, audioDuration: 1,
            measuredAt: .now, chip: "Apple M5 Max", macosVersion: "27.0",
            appVersion: BestASRVersion.current
        )
        #expect(degenerate.timesRealtime == 0)
    }

    @Test func `Recommendation data source serializes to the contract strings`() {
        #expect(RecommendationDataSource.measured.rawValue == "measured")
        #expect(RecommendationDataSource.coldStartPrior.rawValue == "cold_start_prior")
    }

    @Test(arguments: RouterProfile.allCases)
    func `Profile weights over the two measured axes sum to one`(profile: RouterProfile) {
        #expect(abs(profile.accuracyWeight + profile.speedWeight - 1.0) < 1e-9)
    }

    @Test func `Accurate profile weighs accuracy above speed and fast does the opposite`() {
        #expect(RouterProfile.high.accuracyWeight > RouterProfile.high.speedWeight)
        #expect(RouterProfile.low.speedWeight > RouterProfile.low.accuracyWeight)
    }
}

struct ModelRegistryTests {
    @Test(arguments: ModelRegistry.supportedModels)
    func `Every supported model has a positive memory estimate`(model: String) throws {
        let req = try ModelRegistry.requirements(for: model)
        #expect(req.memoryGB > 0)
        #expect(req.model == model)
    }

    @Test func `Unknown model is a usage error naming the supported set`() {
        #expect(throws: BestASRError.self) {
            try ModelRegistry.requirements(for: "gigantic-v9")
        }
    }

    @Test func `Profile candidate lists match the cold-start prior spec`() {
        #expect(ModelRegistry.profileModels[.low] == ["tiny", "base", "small"])
        #expect(ModelRegistry.profileModels[.medium] == ["small", "medium"])
        #expect(ModelRegistry.profileModels[.high] == ["medium", "large-v3-turbo", "large-v3"])
        // Top three tiers deliberately share one cold-start list (design D5, #29).
        #expect(ModelRegistry.profileModels[.xhigh] == ModelRegistry.profileModels[.high])
        #expect(ModelRegistry.profileModels[.max] == ModelRegistry.profileModels[.high])
    }

    @Test func `Downgrade chain steps large models toward tiny`() {
        #expect(ModelRegistry.nextSmaller(than: "large-v3") == "medium")
        #expect(ModelRegistry.nextSmaller(than: "large-v3-turbo") == "medium")
        #expect(ModelRegistry.nextSmaller(than: "base") == "tiny")
        #expect(ModelRegistry.nextSmaller(than: "tiny") == nil)
    }

    @Test(arguments: BackendID.allCases)
    func `Each backend offers at least one quantization and a default for every cataloged model`(backend: BackendID) {
        // Grid-scoped (#14): each runnable backend is checked against its own
        // catalog rows (mlx-audio rows are a reference catalog with no
        // backend, #20 — not part of this parameterization).
        let rows = ModelGrid.rows(backend: backend.rawValue, priorityCeiling: nil)
        #expect(!rows.isEmpty, "no grid rows for \(backend)")
        for row in rows {
            let variants = ModelRegistry.quantizations(for: backend, model: row.size)
            #expect(variants.contains(row.quantization), "\(row.modelId) not in registry projection")
            #expect(variants.first == ModelRegistry.defaultQuantization(for: backend, model: row.size))
        }
    }

    @Test func `whisper.cpp quantization table matches the HF distribution`() {
        // Locked to the actual ggerganov/whisper.cpp HF file list (probed
        // 2026-07-02, #5): q5_0 does NOT exist for tiny/base/small (they ship
        // q5_1), and large-v3 ships q5_0 only — a wrong row regenerates the
        // 404-guidance bug this table exists to prevent.
        for model in ["tiny", "base", "small"] {
            #expect(ModelRegistry.quantizations(for: .whisperCpp, model: model) == ["q5_1", "q8_0"])
        }
        for model in ["medium", "large-v3-turbo"] {
            #expect(ModelRegistry.quantizations(for: .whisperCpp, model: model) == ["q5_0", "q8_0"])
        }
        #expect(ModelRegistry.quantizations(for: .whisperCpp, model: "large-v3") == ["q5_0"])
        // Default = first entry, so cold-start never proposes a 404 file.
        #expect(ModelRegistry.defaultQuantization(for: .whisperCpp, model: "tiny") == "q5_1")
        #expect(ModelRegistry.defaultQuantization(for: .whisperCpp, model: "medium") == "q5_0")
        // Unknown models get no guessed row (drift guard - see registry comment).
        #expect(ModelRegistry.quantizations(for: .whisperCpp, model: "large-v4").isEmpty)
    }
}
