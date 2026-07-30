import Foundation
import Testing

@testable import BestASRKit

/// #111 provenance schema: two optional fields (`run_kind`,
/// `decode_deterministic`) added to the measurement + submission rows, mirroring
/// the `hf_revision` precedent — optional, nil-defaulted, snake_case, and
/// backward-compatible via synthesized Codable (nil optionals encode as absent
/// keys, absent keys decode as nil).
struct RunKindDecodeDeterministicTests {
    private func iso8601Encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func iso8601Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: MeasurementRow

    @Test func `Legacy measurement JSON without the new keys decodes to nil`() throws {
        // A row written before #111 — no run_kind / decode_deterministic keys.
        let legacy = """
        {"app_version":"0.3.0","corpus_id":"c","error_rate":0.2,"machine_id":"m","macos_version":"27.0","measured_at":"2026-01-01T00:00:00Z","metric_kind":"wer","model_id":"whisperkit|whisper|tiny|default","peak_memory_gb":0.4,"rtf":0.1,"warmup_seconds":2}
        """
        let row = try iso8601Decoder().decode(MeasurementRow.self, from: Data(legacy.utf8))
        #expect(row.runKind == nil)
        #expect(row.decodeDeterministic == nil)
    }

    @Test func `Measurement row round-trips the new fields preserving values`() throws {
        let row = MeasurementRow(
            modelId: "whisperkit|whisper|tiny|default", corpusId: "c", machineId: "m",
            measuredAt: Date(timeIntervalSince1970: 1_800_000_000), metricKind: .wer,
            errorRate: 0.1, rtf: 0.2, peakMemoryGB: 1, warmupSeconds: 1,
            appVersion: "0.4.0", macosVersion: "27.0",
            runKind: "release-sweep", decodeDeterministic: true)
        let json = String(decoding: try iso8601Encoder().encode(row), as: UTF8.self)
        // snake_case keys on disk (spec: BCNF store field naming).
        #expect(json.contains("\"run_kind\""))
        #expect(json.contains("\"decode_deterministic\""))
        let decoded = try iso8601Decoder().decode(MeasurementRow.self, from: Data(json.utf8))
        #expect(decoded == row)
        #expect(decoded.runKind == "release-sweep")
        #expect(decoded.decodeDeterministic == true)
    }

    @Test func `Nil new fields encode as absent keys, mirroring hf_revision`() throws {
        // Default init leaves runKind / decodeDeterministic (and hfRevision) nil;
        // synthesized Codable omits nil optionals, so the keys never appear.
        let row = MeasurementRow(
            modelId: "whisperkit|whisper|tiny|default", corpusId: "c", machineId: "m",
            measuredAt: Date(timeIntervalSince1970: 1_800_000_000), metricKind: .wer,
            errorRate: 0.1, rtf: 0.2, peakMemoryGB: 1, warmupSeconds: 1,
            appVersion: "0.4.0", macosVersion: "27.0")
        let json = String(decoding: try iso8601Encoder().encode(row), as: UTF8.self)
        #expect(!json.contains("run_kind"))
        #expect(!json.contains("decode_deterministic"))
        #expect(!json.contains("hf_revision"))  // same omit-nil behavior we mirror
    }

    // MARK: SubmissionRow (denormalized publish row carries the same provenance)

    @Test func `Submission packaging threads the new provenance through`() throws {
        let row = MeasurementRow(
            modelId: "whisperkit|whisper|large-v3|default", corpusId: "abc123abc123",
            machineId: MachineRow.id(chip: "Apple M5 Max", unifiedMemoryGB: 128),
            measuredAt: Date(timeIntervalSince1970: 1_752_800_000), metricKind: .cer,
            errorRate: 0.12, rtf: 0.14, peakMemoryGB: 3.1, warmupSeconds: 8.0,
            appVersion: "0.14.0", macosVersion: "26.0",
            runKind: "release-sweep", decodeDeterministic: true)
        let submissions = SubmissionPackager.package(
            local: [row], machines: [MachineRow(chip: "Apple M5 Max", unifiedMemoryGB: 128)],
            canonicalCorpusIds: ["abc123abc123"], publishedKeys: [], contributor: "che")
        #expect(submissions.count == 1)
        #expect(submissions[0].runKind == "release-sweep")
        #expect(submissions[0].decodeDeterministic == true)

        // JSONL round-trips the snake_case keys.
        let jsonl = try SubmissionPackager.encodeJSONL(submissions)
        #expect(jsonl.contains("\"run_kind\""))
        #expect(jsonl.contains("\"decode_deterministic\""))
        let decoded = try iso8601Decoder().decode(
            SubmissionRow.self, from: Data(jsonl.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        #expect(decoded.runKind == "release-sweep")
        #expect(decoded.decodeDeterministic == true)
    }

    @Test func `Legacy submission JSON without the new keys decodes to nil`() throws {
        let legacy = """
        {"app_version":"0.14.0","chip":"Apple M5 Max","contributor":"che","corpus_id":"abc123abc123","error_rate":0.12,"machine_id":"deadbeefdead","macos_version":"26.0","measured_at":"2026-01-01T00:00:00Z","metric_kind":"cer","model_id":"whisperkit|whisper|large-v3|default","peak_memory_gb":3.1,"rtf":0.14,"unified_memory_gb":128,"warmup_seconds":8}
        """
        let row = try iso8601Decoder().decode(SubmissionRow.self, from: Data(legacy.utf8))
        #expect(row.runKind == nil)
        #expect(row.decodeDeterministic == nil)
    }
}
