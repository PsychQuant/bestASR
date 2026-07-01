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
        #expect(RouterProfile.accurate.accuracyWeight > RouterProfile.accurate.speedWeight)
        #expect(RouterProfile.fast.speedWeight > RouterProfile.fast.accuracyWeight)
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
        #expect(ModelRegistry.profileModels[.fast] == ["tiny", "base", "small"])
        #expect(ModelRegistry.profileModels[.balanced] == ["small", "medium"])
        #expect(ModelRegistry.profileModels[.accurate] == ["medium", "large-v3-turbo", "large-v3"])
    }

    @Test func `Downgrade chain steps large models toward tiny`() {
        #expect(ModelRegistry.nextSmaller(than: "large-v3") == "medium")
        #expect(ModelRegistry.nextSmaller(than: "large-v3-turbo") == "medium")
        #expect(ModelRegistry.nextSmaller(than: "base") == "tiny")
        #expect(ModelRegistry.nextSmaller(than: "tiny") == nil)
    }

    @Test(arguments: BackendID.allCases)
    func `Each backend offers at least one quantization and a default`(backend: BackendID) {
        let variants = ModelRegistry.quantizations[backend] ?? []
        #expect(!variants.isEmpty)
        #expect(variants.contains(ModelRegistry.defaultQuantization(for: backend)))
    }
}
