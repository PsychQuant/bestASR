import Foundation
import Testing

@testable import BestASRKit

/// Round-4 verify findings C2 and C3 (#183).
///
/// Two defects with one shape: `identityComplete` was a STORED field, so it
/// could be absent (legacy JSON) or forgotten (a rebuild), and both failure
/// modes resolved to the unsafe answer. Deriving it from the record's own
/// components removes the ways to get it wrong rather than adding places to
/// remember it.
struct IdentityCompletenessTests {

    /// C2 — a record written before this change has neither new key.
    @Test func `A record written by an earlier version still decodes`() throws {
        let legacy = #"""
        {"backend":"whisperkit","model":"tiny","quantization":"q5_1","language":"en",
         "metricKind":"wer","errorRate":0.1,"rtf":0.1,"peakMemoryGB":1.0,
         "audioDuration":1.0,"measuredAt":0,"chip":"Apple M5 Max",
         "macosVersion":"27.0","appVersion":"0.3.0"}
        """#
        // Swift's synthesized Decodable does NOT consult property defaults, so
        // a non-optional stored field here threw keyNotFound — and the caller
        // (BenchmarkStore.migrateLegacyIfPresent) reads that as "corrupt" and
        // renames the file, dropping the user's whole measurement history.
        let record = try JSONDecoder().decode(BenchmarkRecord.self, from: Data(legacy.utf8))
        #expect(record.model == "tiny")
        #expect(record.identity == nil)
        // No identity means nothing to compare against — fail closed.
        #expect(record.identityComplete == false)
    }

    /// C3 — the flag must survive the paths that rebuild a record.
    @Test func `Collapsing several measurements keeps the completeness verdict`() throws {
        // TWO CORPORA, not two timestamps on one. `latestMeasurements` keeps
        // the newest row per (model, corpus, machine), so two measurements of
        // the same corpus collapse to one BEFORE the group-collapse runs and
        // `guard group.count > 1` short-circuits — the first draft of this
        // test made exactly that mistake and passed while the defect stood.
        let corpora = (0..<2).map { i in
            CorpusRow(
                name: "c\(i)", language: "en",
                audioSHA256: String(repeating: "\(i)", count: 64),
                referenceSHA256: "", duration: 30, audioPath: "", referencePath: "")
        }
        func row(_ corpus: CorpusRow, _ at: TimeInterval) -> MeasurementRow {
            MeasurementRow(
                modelId: "mlx-audio|mms|1b|\(Quantization.unknown.serialised)",
                corpusId: corpus.corpusId, machineId: "h",
                measuredAt: Date(timeIntervalSince1970: at), metricKind: .wer,
                errorRate: 0.1, rtf: 0.1, peakMemoryGB: 1, warmupSeconds: 1,
                appVersion: "0.3.0", macosVersion: "27.0")
        }
        let snapshot = BenchmarkStore.Snapshot(
            machines: [], models: [], corpora: corpora,
            measurements: [row(corpora[0], 1_000), row(corpora[1], 2_000)], warnings: [])

        let records = snapshot.projectedRecords()
        #expect(records.count == 1)
        let collapsed = try #require(records.first)
        #expect(collapsed.identity == ModelID(family: "mms", size: "1b"))
        #expect(collapsed.identityComplete == false)
    }

    /// C3 — Router.aggregate rebuilds too, for every group.
    @Test func `Router aggregation keeps the completeness verdict`() throws {
        let identity = try #require(ModelID(family: "mms", size: "1b"))
        func record(_ at: TimeInterval) -> BenchmarkRecord {
            BenchmarkRecord(
                backend: "mlx-audio", model: "mms/1b",
                quantization: Quantization.unknown.serialised,
                identity: identity, language: "en", metricKind: .wer,
                errorRate: 0.1, rtf: 0.1, peakMemoryGB: 1, audioDuration: 10,
                measuredAt: Date(timeIntervalSince1970: at), chip: "Apple M5 Max",
                macosVersion: "27.0", appVersion: "0.3.0")
        }
        let aggregated = Router.aggregate([record(1_000), record(2_000)])
        #expect(aggregated.count == 1)
        let only = try #require(aggregated.first)
        #expect(only.runs == 2)
        #expect(only.record.identity == identity)
        #expect(only.record.identityComplete == false)
    }

    /// The verdict is a function of the record, so it cannot disagree with it.
    @Test func `Completeness is derived, so a rebuild cannot flip it`() throws {
        let identity = try #require(ModelID(family: "whisper", size: "tiny"))
        let complete = BenchmarkRecord(
            backend: "whisperkit", model: "tiny", quantization: "q5_1",
            identity: identity, language: "en", metricKind: .wer,
            errorRate: 0.1, rtf: 0.1, peakMemoryGB: 1, audioDuration: 10,
            measuredAt: Date(timeIntervalSince1970: 1), chip: "x",
            macosVersion: "27.0", appVersion: "0.3.0")
        #expect(complete.identityComplete)

        // Same record, quantization nobody recorded.
        let unrecorded = BenchmarkRecord(
            backend: "whisperkit", model: "tiny",
            quantization: Quantization.unknown.serialised,
            identity: identity, language: "en", metricKind: .wer,
            errorRate: 0.1, rtf: 0.1, peakMemoryGB: 1, audioDuration: 10,
            measuredAt: Date(timeIntervalSince1970: 1), chip: "x",
            macosVersion: "27.0", appVersion: "0.3.0")
        #expect(unrecorded.identityComplete == false)
    }
}

/// Round-4 verify finding C6 (#183).
struct MemoryEstimateCollisionTests {
    @Test func `Two precisions of one model do not trap the estimate table`() throws {
        // #35 verify M2 put `uniquingKeysWith: max` there for TWO reasons and
        // #183 removed it citing only one. Keying by identity does end the
        // cross-family collision (sensevoice small vs whisper small). It does
        // NOT end the second: the same identity at two precisions, which this
        // change's own ModelGrid doc calls normal ("more than one row is
        // normal — they are quantization variants of the same model").
        // whisper.cpp already ships two rows per identity and is out of the
        // filter only by accident of which backends it lists.
        let whisperSmall = try #require(ModelID(family: "whisper", size: "small"))
        // A second precision row for a live-engine backend must not turn
        // `requirements(for:)` — called inside ColdStartPrior.fits()'s loop —
        // into a fatalError.
        let estimate = try ModelRegistry.requirements(for: whisperSmall)
        #expect(estimate.memoryGB > 0)

        // The conservative reading is the larger figure, which is what the
        // deleted comment asked for.
        let rows = ModelGrid.rows.filter {
            $0.backend == ModelGrid.backendWhisperCpp && $0.identity == whisperSmall
        }
        #expect(rows.count == 2, "whisper.cpp ships two precisions of this identity")
        #expect(Set(rows.map(\.estMemoryGB)).count == 1,
                "same estimate today — the trap is armed by the SHAPE, not by today's data")
    }
}

/// Round-9 verify replaced the excluding version of this rule: measured
/// against the store, its criterion ran BACKWARDS — it dropped the 44
/// measurements frozen by a commit sha and admitted the 47 whose precision was
/// a dependency default, because it asked today's catalog instead of the
/// record. Records now rank and say what they cannot vouch for.
struct ArtifactAttestationTests {
    private func snapshot(
        modelId: String, hfRevision: String?
    ) -> BenchmarkStore.Snapshot {
        let corpus = CorpusRow(
            name: "c", language: "en", audioSHA256: String(repeating: "c", count: 64),
            referenceSHA256: "", duration: 30, audioPath: "", referencePath: "")
        return BenchmarkStore.Snapshot(
            machines: [], models: [], corpora: [corpus],
            measurements: [MeasurementRow(
                modelId: modelId, corpusId: corpus.corpusId, machineId: "h",
                measuredAt: Date(timeIntervalSince1970: 1_000), metricKind: .wer,
                errorRate: 0.1, rtf: 0.1, peakMemoryGB: 1, warmupSeconds: 1,
                appVersion: "0.3.0", macosVersion: "27.0", hfRevision: hfRevision)],
            warnings: [])
    }

    @Test func `A stored placeholder does not become attested because the catalog states a value today`() throws {
        // The 47: measured when the engine called load() with no precision
        // argument. The catalog states `.named("fp16")` NOW — a fact about
        // today, not about the run that produced this number.
        let record = try #require(
            snapshot(modelId: "fluid-sensevoice|sensevoice|small|default", hfRevision: nil)
                .projectedRecords().first)
        #expect(record.quantization == "fp16", "the grouping label still comes from the catalog")
        #expect(record.attestsArtifact == false, "the catalog vouched for a past measurement")
    }

    @Test func `A stored placeholder IS attested when the measurement carries its own pin`() throws {
        // The 44: stored `default`, but the measurement recorded the revision
        // it was seeded with (#16). The artifact is frozen; the label is not.
        let record = try #require(
            snapshot(modelId: "mlx-audio|moonshine|base|default",
                     hfRevision: "7a73d8d55ac0ba2ef3ae761593f6784b51f96dcf")
                .projectedRecords().first)
        #expect(record.attestsArtifact, "a sha-pinned measurement was called unattested")
    }

    @Test func `A concrete stored quantization attests without needing a pin`() throws {
        let record = try #require(
            snapshot(modelId: "whisper.cpp|whisper|tiny|q5_1", hfRevision: nil)
                .projectedRecords().first)
        #expect(record.attestsArtifact)
    }

    @Test func `A candidate merged from an attested and an unattested run vouches for neither`() throws {
        // Two corpora, so the collapse actually runs — `latestMeasurements`
        // keeps one row per (model, corpus, machine) and the per-candidate
        // group therefore has two members. A single-corpus fixture returns
        // early at `guard group.count > 1` and observes nothing, which is how
        // round-4's C3 test managed to be vacuous about exactly this field.
        let corpora = (0..<2).map { i in
            CorpusRow(
                name: "c\(i)", language: "en",
                audioSHA256: String(repeating: "\(i)", count: 64),
                referenceSHA256: "", duration: 30, audioPath: "", referencePath: "")
        }
        let id = "mlx-audio|moonshine|base|default"
        let snapshot = BenchmarkStore.Snapshot(
            machines: [], models: [], corpora: corpora,
            measurements: [
                MeasurementRow(
                    modelId: id, corpusId: corpora[0].corpusId, machineId: "h",
                    measuredAt: Date(timeIntervalSince1970: 1_000), metricKind: .wer,
                    errorRate: 0.1, rtf: 0.1, peakMemoryGB: 1, warmupSeconds: 1,
                    appVersion: "0.3.0", macosVersion: "27.0",
                    hfRevision: "7a73d8d55ac0ba2ef3ae761593f6784b51f96dcf"),
                MeasurementRow(
                    modelId: id, corpusId: corpora[1].corpusId, machineId: "h",
                    measuredAt: Date(timeIntervalSince1970: 2_000), metricKind: .wer,
                    errorRate: 0.3, rtf: 0.1, peakMemoryGB: 1, warmupSeconds: 1,
                    appVersion: "0.3.0", macosVersion: "27.0", hfRevision: nil),
            ],
            warnings: [])

        let records = snapshot.projectedRecords()
        let merged = try #require(records.first)
        #expect(records.count == 1, "the two runs did not collapse into one candidate")
        #expect(merged.errorRate == 0.2, "the collapse did not run — this is the vacuity guard")
        #expect(merged.attestsArtifact == false,
                "a merged candidate vouched for itself when one of its runs could not")
    }

    @Test func `An unattested record ranks, and the recommendation says it cannot vouch`() throws {
        let unattested = BenchmarkRecord(
            backend: BackendID.whisperKit.rawValue, model: "whisper/large-v3-turbo",
            quantization: Quantization.deferred(.runtime).serialised,
            identity: ModelID(family: "whisper", size: "large-v3-turbo"),
            artifactAttested: false,
            language: "zh", metricKind: .cer, errorRate: 0.05, rtf: 1.0 / 12.0,
            peakMemoryGB: 3, audioDuration: 60,
            measuredAt: Date(timeIntervalSince1970: 1_780_000_000),
            chip: Fixtures.m5Max.chip, macosVersion: "27.0", appVersion: BestASRVersion.current)

        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "zh",
            backendOverride: nil, modelOverride: nil,
            records: [unattested], availability: [.whisperKit: true])

        // Ranked — the evidence is not deleted.
        #expect(rec.dataSource == .measured)
        #expect(rec.model == "whisper/large-v3-turbo")
        // And named — the reader is told what it cannot promise.
        #expect(rec.warnings.contains { $0.contains("does not record which artifact") },
                "an unattested recommendation went out silently; warnings: \(rec.warnings)")
        #expect(rec.reason.contains { $0.contains("not guaranteed like-for-like") },
                "the pool's unattested count was not reported; reasons: \(rec.reason)")
    }

    @Test func `An attested recommendation carries no such warning`() throws {
        let attested = Fixtures.record(
            backend: .whisperCpp, size: "tiny", quantization: "q5_1", language: "zh")
        #expect(attested.attestsArtifact == false, "fixture default carries no attestation")
        let rec = try Router.recommend(
            host: Fixtures.m5Max, profile: .high, requestedLanguage: "zh",
            backendOverride: nil, modelOverride: nil,
            records: [BenchmarkRecord(
                backend: attested.backend, model: attested.model,
                quantization: attested.quantization, identity: attested.identity,
                artifactAttested: true, language: attested.language,
                metricKind: attested.metricKind, errorRate: attested.errorRate,
                rtf: attested.rtf, peakMemoryGB: attested.peakMemoryGB,
                audioDuration: attested.audioDuration, measuredAt: attested.measuredAt,
                chip: attested.chip, macosVersion: attested.macosVersion,
                appVersion: attested.appVersion)],
            availability: [.whisperCpp: true])
        #expect(!rec.warnings.contains { $0.contains("does not record which artifact") })
    }
}
