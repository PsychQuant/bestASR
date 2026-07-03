import Foundation
import Testing

@testable import BestASRKit

// #29 effort-ordinal profiles: 5-tier ladder, max = pure accuracy argmax with
// a speed tie-break, and an `auto` default that adapts to dynamic machine
// conditions without ever overriding an explicit ordinal.

private func record(
    model: String, backend: String = "whisperkit", quantization: String = "default",
    cer: Double, xRealtime: Double
) -> BenchmarkRecord {
    BenchmarkRecord(
        backend: backend, model: model, quantization: quantization, language: "ja",
        metricKind: .cer, errorRate: cer, rtf: 1.0 / xRealtime, peakMemoryGB: 1,
        audioDuration: 10, measuredAt: Date(timeIntervalSince1970: 0),
        chip: "Apple M5 Max", macosVersion: "26.0", appVersion: BestASRVersion.current)
}

struct OrdinalProfileTests {
    @Test func `ladder has five ordinals with anchored weights`() {
        #expect(RouterProfile.allCases == [.low, .medium, .high, .xhigh, .max])
        #expect(RouterProfile.low.accuracyWeight == 0.267)
        #expect(RouterProfile.medium.accuracyWeight == 0.5)
        #expect(RouterProfile.high.accuracyWeight == 0.8)
        #expect(RouterProfile.xhigh.accuracyWeight == 0.9)
        #expect(RouterProfile.max.accuracyWeight == 1.0)
        #expect(RouterProfile.max.speedWeight == 0.0)
    }
}

struct MaxArgmaxRankingTests {
    @Test func `max picks the most accurate regardless of a huge speed gap`() {
        let ranked = Ranking.rank(
            [
                record(model: "large-v3", cer: 0.05, xRealtime: 2.0),
                record(model: "small", cer: 0.06, xRealtime: 40.0),
            ], profile: .max)
        #expect(ranked.first?.record.model == "large-v3")
    }

    @Test func `max breaks an equal-accuracy tie to the faster candidate`() {
        let ranked = Ranking.rank(
            [
                record(model: "slow-tie", cer: 0.05, xRealtime: 2.0),
                record(model: "fast-tie", cer: 0.05, xRealtime: 12.0),
                record(model: "worse", cer: 0.06, xRealtime: 40.0),
            ], profile: .max)
        #expect(ranked.first?.record.model == "fast-tie")
    }

    @Test func `medium profile equal scores also tie-break deterministically`() {
        // The explicit tie-break is global, not max-only (#29 verify #6): two
        // candidates that normalize to the same weighted score under medium
        // still resolve to a stable order (faster first, then lexicographic).
        let slow = record(model: "m", backend: "a", cer: 0.10, xRealtime: 10)
        let fast = record(model: "m", backend: "b", cer: 0.10, xRealtime: 10)
        let one = Ranking.rank([slow, fast], profile: .medium).map { $0.record.backend }
        let two = Ranking.rank([fast, slow], profile: .medium).map { $0.record.backend }
        #expect(one == two)
    }

    @Test func `full ties fall back to a deterministic lexicographic order`() {
        let a = record(model: "alpha", cer: 0.05, xRealtime: 10)
        let b = record(model: "beta", cer: 0.05, xRealtime: 10)
        #expect(Ranking.rank([b, a], profile: .max).map(\.record.model) == ["alpha", "beta"])
        #expect(Ranking.rank([a, b], profile: .max).map(\.record.model) == ["alpha", "beta"])
    }
}

struct DynamicHostStateTests {
    @Test func `nominal machine reports no pressure`() {
        #expect(DynamicHostState.nominal.isUnderPressure == false)
        #expect(DynamicHostState.nominal.pressureCause == nil)
    }

    @Test func `serious and critical thermal states count as pressure, fair does not`() {
        #expect(
            DynamicHostState(thermalState: .serious, lowPowerModeEnabled: false).pressureCause
                == "thermal state: serious")
        #expect(
            DynamicHostState(thermalState: .critical, lowPowerModeEnabled: false).pressureCause
                == "thermal state: critical")
        #expect(
            DynamicHostState(thermalState: .fair, lowPowerModeEnabled: false).isUnderPressure
                == false)
    }

    @Test func `low power mode counts as pressure`() {
        #expect(
            DynamicHostState(thermalState: .nominal, lowPowerModeEnabled: true).pressureCause
                == "Low Power Mode enabled")
    }

    @Test func `thermal cause outranks low power mode when both apply`() {
        #expect(
            DynamicHostState(thermalState: .critical, lowPowerModeEnabled: true).pressureCause
                == "thermal state: critical")
    }
}

struct ProfileResolutionTests {
    @Test func `auto resolves to medium on an unpressured machine and says so`() throws {
        let resolved = try CommandCore.resolveProfile(named: "auto", dynamicState: .nominal)
        #expect(resolved.profile == .medium)
        #expect(resolved.reasons == ["auto profile resolved to medium (no machine pressure)"])
    }

    @Test func `auto downshifts to low under pressure with the cause disclosed`() throws {
        let resolved = try CommandCore.resolveProfile(
            named: "auto",
            dynamicState: DynamicHostState(thermalState: .serious, lowPowerModeEnabled: false))
        #expect(resolved.profile == .low)
        #expect(resolved.reasons == ["auto profile downshifted to low (thermal state: serious)"])
    }

    @Test func `an explicit ordinal ignores machine pressure`() throws {
        let resolved = try CommandCore.resolveProfile(
            named: "max",
            dynamicState: DynamicHostState(thermalState: .critical, lowPowerModeEnabled: true))
        #expect(resolved.profile == .max)
        #expect(resolved.reasons.isEmpty)
    }

    @Test func `legacy profile names fail with their ordinal replacement`() {
        do {
            _ = try CommandCore.parseProfile("balanced")
            Issue.record("balanced should have thrown")
        } catch let BestASRError.usage(message) {
            #expect(message.contains("medium"))
        } catch { Issue.record("unexpected error: \(error)") }
        do {
            _ = try CommandCore.parseProfile("fast")
            Issue.record("fast should have thrown")
        } catch let BestASRError.usage(message) {
            #expect(message.contains("low"))
        } catch { Issue.record("unexpected error: \(error)") }
        do {
            _ = try CommandCore.parseProfile("accurate")
            Issue.record("accurate should have thrown")
        } catch let BestASRError.usage(message) {
            #expect(message.contains("high"))
            #expect(message.contains("max"))
        } catch { Issue.record("unexpected error: \(error)") }
    }

    @Test func `unknown profile values list the ordinal ladder but not auto`() {
        // parseProfile is the explicit-ordinal gate; `auto` is resolved above it
        // and rejected by benchmark, so the message must not advertise auto
        // (#29 verify #2/#3 — `benchmark --profile auto` was self-contradictory).
        do {
            _ = try CommandCore.parseProfile("turbo")
            Issue.record("turbo should have thrown")
        } catch let BestASRError.usage(message) {
            #expect(message.contains("low, medium, high, xhigh, max"))
            #expect(!message.contains("auto"))
        } catch { Issue.record("unexpected error: \(error)") }
    }

    @Test func `benchmark rejects auto with a message that does not claim auto is supported`() {
        // benchmark calls parseProfile directly (no auto layer); the error must
        // not list auto as supported (#29 verify #2/#3).
        do {
            _ = try CommandCore.parseProfile("auto")
            Issue.record("auto should have thrown on the benchmark path")
        } catch let BestASRError.usage(message) {
            #expect(message.contains("unknown profile: 'auto'"))
            #expect(!message.contains("supported profiles are auto"))
        } catch { Issue.record("unexpected error: \(error)") }
    }
}

struct DiagnoseAutoWiringTests {
    @Test func `diagnose surfaces the same auto downshift as the real runs`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let core = CommandCore(
            engines: [MockEngine.fixed(.whisperKit)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            dynamicHost: {
                DynamicHostState(thermalState: .serious, lowPowerModeEnabled: false)
            })
        let output = try await core.diagnose()
        // #29 verify #1/#9/#10: diagnose must not pin medium behind the user's
        // back — under pressure it discloses the low downshift like the rest.
        #expect(output.contains("auto profile downshifted to low (thermal state: serious)"))
    }
}

struct AutoProfileWiringTests {
    @Test func `auto flows through the recommendation with the downshift reason first`()
        async throws
    {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let core = CommandCore(
            engines: [MockEngine.fixed(.whisperKit)],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            dynamicHost: {
                DynamicHostState(thermalState: .serious, lowPowerModeEnabled: false)
            })
        let rec = try await core.resolveRecommendation(
            selection: SelectionRequest(
                profileName: "auto", backendOverride: nil, modelOverride: nil,
                requestedLanguage: "auto"),
            language: nil)
        #expect(rec.profile == .low)
        #expect(rec.reason.first == "auto profile downshifted to low (thermal state: serious)")
    }
}
