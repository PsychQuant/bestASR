import Foundation
import Testing
@testable import BestASRKit

private let bothAvailable: [BackendID: Bool] = [.whisperKit: true, .whisperCpp: true]
private let allThreeAvailable: [BackendID: Bool] = [
    .whisperKit: true, .whisperCpp: true, .fluidParakeet: true,
]

/// #35 (spec asr-routing "Rank candidates by measured benchmark data"):
/// candidate enumeration spans model families — a fluid-parakeet candidate
/// wins on merit, loses without language coverage, and the cold-start prior
/// never proposes an unmeasured family.
struct RouterCrossFamilyTests {
    @Test func `Cross-family candidate wins on measured merit`() throws {
        let records = [
            Fixtures.record(backend: .whisperKit, model: "large-v3-turbo",
                            language: "en", metricKind: .wer,
                            errorRate: 0.12, timesRealtime: 12),
            Fixtures.record(backend: .fluidParakeet, model: "0.6b-v3",
                            language: "en", metricKind: .wer,
                            errorRate: 0.04, timesRealtime: 30),
        ]
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "en",
            backendOverride: nil, modelOverride: nil,
            records: records, availability: allThreeAvailable
        )
        #expect(rec.backend == .fluidParakeet)
        #expect(rec.model == "0.6b-v3")
        #expect(rec.dataSource == .measured)
    }

    @Test func `Family without language coverage loses naturally`() throws {
        // zh has whisper measurements only — family diversity never overrides
        // measured evidence (spec scenario).
        let records = [
            Fixtures.record(backend: .whisperKit, model: "large-v3-turbo",
                            language: "zh", errorRate: 0.06, timesRealtime: 12),
            Fixtures.record(backend: .fluidParakeet, model: "0.6b-v3",
                            language: "en", metricKind: .wer,
                            errorRate: 0.04, timesRealtime: 30),
        ]
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "zh",
            backendOverride: nil, modelOverride: nil,
            records: records, availability: allThreeAvailable
        )
        #expect(rec.backend == .whisperKit)
    }

    @Test func `Explicit fluid-parakeet backend override locks the family`() throws {
        let records = [
            Fixtures.record(backend: .whisperKit, model: "large-v3-turbo",
                            language: "en", metricKind: .wer,
                            errorRate: 0.04, timesRealtime: 12),
            Fixtures.record(backend: .fluidParakeet, model: "0.6b-v3",
                            language: "en", metricKind: .wer,
                            errorRate: 0.12, timesRealtime: 30),
        ]
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "en",
            backendOverride: "fluid-parakeet", modelOverride: nil,
            records: records, availability: allThreeAvailable
        )
        #expect(rec.backend == .fluidParakeet)
    }

    @Test func `Parakeet model override is accepted as a supported model`() throws {
        // Pre-#35 the registry rejected non-whisper sizes as usage errors.
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "en",
            backendOverride: "fluid-parakeet", modelOverride: "0.6b-v3",
            records: [
                Fixtures.record(backend: .fluidParakeet, model: "0.6b-v3",
                                language: "en", metricKind: .wer,
                                errorRate: 0.05, timesRealtime: 30)
            ],
            availability: allThreeAvailable
        )
        #expect(rec.model == "0.6b-v3")
    }

    @Test func `Locked fluid-parakeet without records routes to its own catalog model`() throws {
        // Verify H2 (#35): the natural "benchmarked whisper, now try parakeet"
        // first step — no parakeet records, --backend fluid-parakeet, no
        // --model. The cold-start prior only knows whisper sizes; the router
        // must fall back to the locked backend's own catalog instead of
        // throwing about a whisper model the user never asked for.
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "en",
            backendOverride: "fluid-parakeet", modelOverride: nil,
            records: [], availability: allThreeAvailable
        )
        #expect(rec.backend == .fluidParakeet)
        #expect(rec.model == "0.6b-v3")
        #expect(rec.dataSource == .coldStartPrior)
    }

    @Test func `A measured-but-worse parakeet zh record never outranks whisper`() throws {
        // Codex finding (#35 verify): the zh fairness case with BOTH families
        // measured — family diversity must not override measured evidence.
        let records = [
            Fixtures.record(backend: .whisperKit, model: "large-v3-turbo",
                            language: "zh", errorRate: 0.06, timesRealtime: 12),
            Fixtures.record(backend: .fluidParakeet, model: "0.6b-v3",
                            language: "zh", errorRate: 0.55, timesRealtime: 30),
        ]
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "zh",
            backendOverride: nil, modelOverride: nil,
            records: records, availability: allThreeAvailable
        )
        #expect(rec.backend == .whisperKit)
    }

    @Test func `Cross-family backend and model mismatch fails loud as a usage error`() throws {
        // Codex + Security L5 (#35 verify): whisperkit cannot run the
        // parakeet size — the router must throw, never silently fall back.
        #expect(throws: BestASRError.self) {
            _ = try Router.recommend(
                host: Fixtures.m5Max, profile: .high, requestedLanguage: "en",
                backendOverride: "whisperkit", modelOverride: "0.6b-v3",
                records: [], availability: allThreeAvailable
            )
        }
    }

    @Test func `Cold start still prefers the whisper prior over an unmeasured family`() throws {
        // No records at all: the cold-start prior stays on the whisper chain
        // (an unmeasured family must not be recommended without evidence).
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "en",
            backendOverride: nil, modelOverride: nil,
            records: [], availability: allThreeAvailable
        )
        #expect(rec.backend == .whisperKit)
        #expect(rec.dataSource == .coldStartPrior)
    }
}

struct RouterMeasuredTests {
    /// Spec SBE: same measurements, profile flips the winner.
    @Test(arguments: [
        (RouterProfile.high, "large-v3-turbo"),
        (RouterProfile.low, "small"),
    ])
    func `Profile flips the winner on the same measurements`(
        profile: RouterProfile, expectedModel: String
    ) throws {
        let records = [
            Fixtures.record(backend: .whisperKit, model: "large-v3-turbo",
                            errorRate: 0.05, timesRealtime: 12),
            Fixtures.record(backend: .whisperCpp, model: "small", quantization: "q5_0",
                            errorRate: 0.15, timesRealtime: 20),
        ]
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: profile, requestedLanguage: "zh",
            backendOverride: nil, modelOverride: nil,
            records: records, availability: bothAvailable
        )
        #expect(rec.model == expectedModel)
        #expect(rec.dataSource == .measured)
        #expect(rec.measured != nil)
    }

    @Test func `Measured recommendation cites its numbers in the reasons`() throws {
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "zh",
            backendOverride: nil, modelOverride: nil,
            records: [Fixtures.record(errorRate: 0.05, timesRealtime: 12)],
            availability: bothAvailable
        )
        #expect(rec.reason.contains { $0.contains("CER") && $0.contains("5.0%") })
        #expect(rec.reason.contains { $0.contains("12.0x realtime") })
    }

    @Test func `Stale-machine records are ignored and routing cold-starts`() throws {
        let staleRecords = [Fixtures.record(chip: "Apple M1")]  // host is M5 Max
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .medium, requestedLanguage: "zh",
            backendOverride: nil, modelOverride: nil,
            records: staleRecords, availability: bothAvailable
        )
        #expect(rec.dataSource == .coldStartPrior)
    }

    @Test func `Language-mismatched records are not used`() throws {
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .medium, requestedLanguage: "en",
            backendOverride: nil, modelOverride: nil,
            records: [Fixtures.record(language: "zh")],
            availability: bothAvailable
        )
        #expect(rec.dataSource == .coldStartPrior)
    }

    @Test func `Unavailable-backend records are not used`() throws {
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .medium, requestedLanguage: "zh",
            backendOverride: nil, modelOverride: nil,
            records: [Fixtures.record(backend: .whisperCpp, quantization: "q5_0")],
            availability: [.whisperKit: true, .whisperCpp: false]
        )
        #expect(rec.dataSource == .coldStartPrior)
        #expect(rec.backend == .whisperKit)
    }
}

struct RouterColdStartTests {
    @Test func `Cold start recommends whisperkit from the prior and suggests benchmarking`() throws {
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .medium, requestedLanguage: nil,
            backendOverride: nil, modelOverride: nil,
            records: [], availability: bothAvailable
        )
        #expect(rec.backend == .whisperKit)
        #expect(ModelRegistry.profileModels[.medium]!.contains(rec.model))
        #expect(rec.dataSource == .coldStartPrior)
        #expect(rec.measured == nil)
        #expect(rec.reason.contains { $0.contains("bestasr benchmark") })
    }

    /// Spec SBE: downgrade steps by available memory.
    @Test(arguments: [
        (137.4, "large-v3", 0),
        (6.0, "medium", 1),
        (3.0, "small", 2),
    ])
    func `Downgrade steps by available unified memory`(
        memoryGB: Double, expected: String, warningCount: Int
    ) {
        let (model, warnings, _) = ColdStartPrior.ensureFits("large-v3", in: memoryGB)
        #expect(model == expected)
        #expect(warnings.count == warningCount)
    }

    @Test func `High profile on a small machine picks a model that fits`() throws {
        let rec = try Router.recommend(
            host: Fixtures.smallMac, profile: .high, requestedLanguage: nil,
            backendOverride: nil, modelOverride: nil,
            records: [], availability: bothAvailable
        )
        // 8 GB fits medium (5) and large-v3-turbo (6) but not large-v3 (10).
        #expect(rec.model == "large-v3-turbo")
    }

    @Test func `Explicit model override is downgraded only when it cannot fit`() throws {
        let rec = try Router.recommend(
            host: Fixtures.smallMac, profile: .high, requestedLanguage: nil,
            backendOverride: nil, modelOverride: "large-v3",
            records: [], availability: bothAvailable
        )
        #expect(rec.model == "medium")  // 10 GB > 8 GB → one step down
        #expect(rec.warnings.contains { $0.contains("large-v3") })
    }
}

struct RouterOverrideTests {
    @Test func `Requested backend unavailable falls back with a warning`() throws {
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .medium, requestedLanguage: nil,
            backendOverride: "whisper.cpp", modelOverride: nil,
            records: [], availability: [.whisperKit: true, .whisperCpp: false]
        )
        #expect(rec.backend == .whisperKit)
        #expect(rec.warnings.contains { $0.contains("whisper.cpp") && $0.contains("unavailable") })
    }

    @Test func `Available requested backend is honored`() throws {
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .medium, requestedLanguage: nil,
            backendOverride: "whisper.cpp", modelOverride: nil,
            records: [], availability: bothAvailable
        )
        #expect(rec.backend == .whisperCpp)
        #expect(rec.quantization == "q5_0")
    }

    @Test func `Unknown backend or model names are usage errors`() {
        #expect(throws: BestASRError.self) {
            _ = try Router.recommend(
                host: Fixtures.m5Max, profile: .medium, requestedLanguage: nil,
                backendOverride: "faster-whisper", modelOverride: nil,
                records: [], availability: bothAvailable
            )
        }
        #expect(throws: BestASRError.self) {
            _ = try Router.recommend(
                host: Fixtures.m5Max, profile: .medium, requestedLanguage: nil,
                backendOverride: nil, modelOverride: "gigantic-v9",
                records: [], availability: bothAvailable
            )
        }
    }

    @Test func `No backend available raises a clear error naming both and install guidance`() {
        do {
            _ = try Router.recommend(
                host: Fixtures.m5Max, profile: .medium, requestedLanguage: nil,
                backendOverride: nil, modelOverride: nil,
                records: [], availability: [.whisperKit: false, .whisperCpp: false]
            )
            Issue.record("expected recommend to throw")
        } catch let error as BestASRError {
            let message = error.errorDescription ?? ""
            #expect(message.contains("whisperkit"))
            #expect(message.contains("whisper.cpp"))
            #expect(message.contains("brew install whisper-cpp"))
            #expect(error.exitCode == 1)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}


