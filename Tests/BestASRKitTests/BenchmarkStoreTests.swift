import Foundation
import Testing
@testable import BestASRKit

// MARK: - 1.1 StoreTables (spec benchmark-store: BCNF four-table store)

struct StoreTablesTests {
    @Test func `Machine id is deterministic over stable facts`() {
        let a = MachineRow(chip: "Apple M5 Max", unifiedMemoryGB: 128)
        let b = MachineRow(chip: "Apple M5 Max", unifiedMemoryGB: 128)
        #expect(a.machineId == b.machineId)
        #expect(a.machineId.count == 12)
        #expect(MachineRow(chip: "Apple M4", unifiedMemoryGB: 16).machineId != a.machineId)
    }

    @Test func `Model id is the four-part key`() {
        let row = ModelRow(
            backend: "mlx-audio", family: "moonshine", size: "base", quantization: "default",
            estMemoryGB: 0.5, priority: 1)
        #expect(row.modelId == "mlx-audio|moonshine|base|default")
    }

    @Test func `Measurement row round-trips through JSON with snake_case keys`() throws {
        // Spec Example: measurement row field names.
        let row = MeasurementRow(
            modelId: "mlx-audio|moonshine|base|default", corpusId: "a1b2c3d4e5f6",
            machineId: "0f1e2d3c4b5a", measuredAt: Date(timeIntervalSince1970: 1_800_000_000),
            metricKind: .wer, errorRate: 0.12, rtf: 0.02, peakMemoryGB: 0.4,
            warmupSeconds: 3.1, appVersion: "0.3.0", macosVersion: "27.0")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(row), as: UTF8.self)
        for key in ["model_id", "corpus_id", "machine_id", "measured_at", "metric_kind",
                    "error_rate", "peak_memory_gb", "warmup_seconds", "app_version",
                    "macos_version"] {
            #expect(json.contains("\"\(key)\""), "missing \(key)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(MeasurementRow.self, from: Data(json.utf8)) == row)
    }

    @Test func `OS version lives on measurements, not machines — FD convergence`() {
        // Spec scenario: same machine across two OS versions → one machine row.
        let m1 = MachineRow(chip: "Apple M5 Max", unifiedMemoryGB: 128)
        let m2 = MachineRow(chip: "Apple M5 Max", unifiedMemoryGB: 128)
        #expect(m1 == m2)  // no OS field to diverge on
    }
}

// MARK: - 1.2 BenchmarkStore (load / append / projection / corrupt rows)

struct BenchmarkStoreTests {
    func makeStore() throws -> BenchmarkStore {
        BenchmarkStore(directory: try makeTempDir().appendingPathComponent("store"))
    }

    func measurement(
        model: String = "m", corpus: String = "c", machine: String = "h",
        at seconds: TimeInterval, errorRate: Double = 0.1
    ) -> MeasurementRow {
        MeasurementRow(
            modelId: model, corpusId: corpus, machineId: machine,
            measuredAt: Date(timeIntervalSince1970: seconds), metricKind: .wer,
            errorRate: errorRate, rtf: 0.1, peakMemoryGB: 1, warmupSeconds: 1,
            appVersion: "0.3.0", macosVersion: "27.0")
    }

    @Test func `Append then load round-trips all four tables`() throws {
        let store = try makeStore()
        try store.upsert(machine: MachineRow(chip: "Apple M5 Max", unifiedMemoryGB: 128))
        try store.seed(models: [
            ModelRow(backend: "mlx-audio", family: "moonshine", size: "base",
                     quantization: "default", estMemoryGB: 0.5, priority: 1)
        ])
        try store.upsert(corpus: CorpusRow(
            name: "jfk", language: "en", audioSHA256: String(repeating: "a", count: 64),
            referenceSHA256: String(repeating: "b", count: 64), duration: 11,
            audioPath: "/tmp/jfk.wav", referencePath: "/tmp/jfk.srt"))
        try store.append(measurement: measurement(at: 1_800_000_000))

        let snapshot = try store.load()
        #expect(snapshot.machines.count == 1)
        #expect(snapshot.models.count == 1)
        #expect(snapshot.corpora.count == 1)
        #expect(snapshot.measurements.count == 1)
        #expect(snapshot.warnings.isEmpty)
    }

    @Test func `Latest projection keeps the newest row per key triple`() throws {
        // Spec scenario: re-benchmark supersedes without deleting.
        let older = measurement(at: 1_000, errorRate: 0.5)
        let newer = measurement(at: 2_000, errorRate: 0.1)
        let other = measurement(model: "m2", at: 500, errorRate: 0.3)
        let latest = BenchmarkStore.latestMeasurements([older, newer, other])
        #expect(latest.count == 2)
        #expect(latest.first(where: { $0.modelId == "m" })?.errorRate == 0.1)
    }

    @Test func `Append-only file retains superseded rows`() throws {
        let store = try makeStore()
        try store.append(measurement: measurement(at: 1_000))
        try store.append(measurement: measurement(at: 2_000))
        let snapshot = try store.load()
        #expect(snapshot.measurements.count == 2)  // history intact
        #expect(BenchmarkStore.latestMeasurements(snapshot.measurements).count == 1)
    }

    @Test func `One malformed line is skipped loudly with table and line number`() throws {
        let store = try makeStore()
        try store.append(measurement: measurement(at: 1_000))
        let url = store.directory.appendingPathComponent("measurements.jsonl")
        var content = try String(contentsOf: url, encoding: .utf8)
        content += "THIS IS NOT JSON\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
        try store.append(measurement: measurement(at: 2_000))

        let snapshot = try store.load()
        #expect(snapshot.measurements.count == 2)  // valid rows survive
        #expect(snapshot.warnings.contains { $0.contains("measurements.jsonl") && $0.contains("2") })
    }

    @Test func `Corpus re-add with a moved path updates rather than duplicates`() throws {
        // Spec corpora scenario: re-add same audio from a new path.
        let store = try makeStore()
        let hash = String(repeating: "c", count: 64)
        let original = CorpusRow(
            name: "talk", language: "zh", audioSHA256: hash,
            referenceSHA256: String(repeating: "d", count: 64), duration: 30,
            audioPath: "/old/talk.wav", referencePath: "/old/talk.srt")
        try store.upsert(corpus: original)
        let moved = CorpusRow(
            name: "talk", language: "zh", audioSHA256: hash,
            referenceSHA256: String(repeating: "d", count: 64), duration: 30,
            audioPath: "/new/talk.wav", referencePath: "/new/talk.srt")
        try store.upsert(corpus: moved)
        let snapshot = try store.load()
        #expect(snapshot.corpora.count == 1)
        #expect(snapshot.corpora[0].audioPath == "/new/talk.wav")
    }
}

// MARK: - 1.3 Legacy migration (spec: One-time legacy migration)

struct LegacyMigrationTests {
    @Test func `Legacy flat cache decomposes into four tables and gains a bak suffix`() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("benchmarks.json")
        let records = [
            Fixtures.record(errorRate: 0.05, timesRealtime: 12),
            Fixtures.record(backend: .whisperCpp, model: "tiny", quantization: "q8_0",
                            errorRate: 0.10, timesRealtime: 60),
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(records).write(to: legacy)

        let store = BenchmarkStore(directory: root.appendingPathComponent("store"))
        let snapshot = try store.load()

        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(atPath: legacy.path + ".bak"))
        #expect(snapshot.measurements.count == 2)
        #expect(snapshot.machines.count == 1)  // both records share the chip
        // Reproduces pre-migration recommendation inputs (error rate / rtf survive).
        let rates = Set(snapshot.measurements.map(\.errorRate))
        #expect(rates == [0.05, 0.10])

        // Idempotent: second load does not re-migrate or duplicate.
        let again = try store.load()
        #expect(again.measurements.count == 2)
    }
}

// MARK: - 5.1 CorpusRegistry (spec corpora)

struct CorpusRegistryTests {
    @Test func `corpus add hashes, probes duration, and lists`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir, seconds: 2.0)
        let srt = dir.appendingPathComponent("truth.srt").path
        try "1\n00:00:00,000 --> 00:00:02,000\nhello world\n".write(
            toFile: srt, atomically: true, encoding: .utf8)
        let store = BenchmarkStore(directory: dir.appendingPathComponent("store"))

        let row = try CorpusRegistry.add(
            audioPath: audio, referencePath: srt, language: "ZH", name: nil, store: store)
        #expect(row.language == "zh")  // normalized
        #expect(row.duration > 1.5)
        #expect(row.audioSHA256.count == 64)

        let table = try CorpusRegistry.listTable(store: store)
        #expect(table.contains("zh"))
        #expect(table.contains(row.corpusId))
    }

    @Test func `Re-adding the same audio from a new path is idempotent`() async throws {
        // Spec scenario: re-add same audio from a new path.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir, seconds: 1.0)
        let srt = dir.appendingPathComponent("t.srt").path
        try "1\n00:00:00,000 --> 00:00:01,000\nhi\n".write(
            toFile: srt, atomically: true, encoding: .utf8)
        let store = BenchmarkStore(directory: dir.appendingPathComponent("store"))
        _ = try CorpusRegistry.add(
            audioPath: audio, referencePath: srt, language: "en", name: "a", store: store)
        let moved = dir.appendingPathComponent("moved.wav")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: audio), to: moved)
        _ = try CorpusRegistry.add(
            audioPath: moved.path, referencePath: srt, language: "en", name: "a", store: store)
        let corpora = try store.load().corpora
        #expect(corpora.count == 1)
        #expect(corpora[0].audioPath == moved.path)
    }

    @Test func `Bad language code is a usage error`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        #expect(throws: BestASRError.self) {
            _ = try CorpusRegistry.add(
                audioPath: audio, referencePath: audio, language: "chinese", name: nil,
                store: BenchmarkStore(directory: dir.appendingPathComponent("s")))
        }
    }
}


// MARK: - #14 verify M-5/M-9 regression locks (projection aggregation)

struct ProjectionAggregationTests {
    func row(model: String, corpus: String, at t: TimeInterval, rate: Double) -> MeasurementRow {
        MeasurementRow(
            modelId: model, corpusId: corpus, machineId: "h",
            measuredAt: Date(timeIntervalSince1970: t), metricKind: .wer,
            errorRate: rate, rtf: 0.1, peakMemoryGB: 1, warmupSeconds: 1,
            appVersion: "0.3.0", macosVersion: "27.0")
    }

    @Test func `One record per candidate across corpora — latest wins`() {
        let corpora = [
            CorpusRow(name: "jfk", language: "en", audioSHA256: String(repeating: "a", count: 64),
                      referenceSHA256: "", duration: 11, audioPath: "", referencePath: ""),
            CorpusRow(name: "osr", language: "en", audioSHA256: String(repeating: "b", count: 64),
                      referenceSHA256: "", duration: 33, audioPath: "", referencePath: ""),
        ]
        let snapshot = BenchmarkStore.Snapshot(
            machines: [MachineRow(chip: "Apple M5 Max", unifiedMemoryGB: 0)],
            models: [],
            corpora: corpora,
            measurements: [
                row(model: "whisperkit|whisper|tiny|default", corpus: corpora[0].corpusId, at: 1_000, rate: 0.0),
                row(model: "whisperkit|whisper|tiny|default", corpus: corpora[1].corpusId, at: 2_000, rate: 0.2),
            ],
            warnings: [])
        // machineId "h" won't join machines — chip empty is fine for this lock.
        let records = snapshot.projectedRecords()
        #expect(records.count == 1)  // one candidate, not one per corpus
        #expect(records[0].errorRate == 0.2)  // newest measurement wins
    }

    @Test func `Legacy family-equals-size ids converge with fresh whisper ids`() {
        let corpus = CorpusRow(name: "c", language: "en", audioSHA256: String(repeating: "c", count: 64),
                               referenceSHA256: "", duration: 30, audioPath: "", referencePath: "")
        let snapshot = BenchmarkStore.Snapshot(
            machines: [], models: [], corpora: [corpus],
            measurements: [
                row(model: "whisperkit|base|base|default", corpus: corpus.corpusId, at: 1_000, rate: 0.9),
                row(model: "whisperkit|whisper|base|default", corpus: corpus.corpusId, at: 2_000, rate: 0.1),
            ],
            warnings: [])
        let records = snapshot.projectedRecords()
        #expect(records.count == 1)  // legacy row superseded, not competing
        #expect(records[0].errorRate == 0.1)
    }
}
