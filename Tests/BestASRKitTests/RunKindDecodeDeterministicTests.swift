import Foundation
import Testing

@testable import BestASRKit
@testable import bestasr

/// #111 provenance schema: two optional fields (`run_kind`,
/// `decode_deterministic`) added to the measurement + submission rows, mirroring
/// the `hf_revision` precedent — optional, nil-defaulted, snake_case, and
/// backward-compatible via synthesized Codable (nil optionals encode as absent
/// keys, absent keys decode as nil).
///
/// #118 narrowed `decode_deterministic` from `Bool?` to `DecodeDeterminism?`:
/// `nil` used to mean BOTH "legacy row" and "this backend ignores the flag".
/// Now the three enum cases record what we KNOW about the decode, and `nil`
/// keeps exactly one meaning — the field was absent (legacy row).
///
/// #120 item 1 locks the "never lie" invariant of the honest gate as a pure,
/// unit-testable helper; item 2 moves `--run-kind` value-domain validation to
/// the CLI boundary.
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

    /// A minimal row whose only interesting field is the determinism condition.
    private func row(_ determinism: DecodeDeterminism?) -> MeasurementRow {
        MeasurementRow(
            modelId: "whisperkit|whisper|tiny|default", corpusId: "c", machineId: "m",
            measuredAt: Date(timeIntervalSince1970: 1_800_000_000), metricKind: .wer,
            errorRate: 0.1, rtf: 0.2, peakMemoryGB: 1, warmupSeconds: 1,
            appVersion: "0.4.0", macosVersion: "27.0",
            runKind: "release-sweep", decodeDeterministic: determinism)
    }

    // MARK: MeasurementRow

    @Test func `Legacy measurement JSON without the new keys decodes to nil`() throws {
        // A row written before #111 — no run_kind / decode_deterministic keys.
        let legacy = """
        {"app_version":"0.3.0","corpus_id":"c","error_rate":0.2,"machine_id":"m","macos_version":"27.0","measured_at":"2026-01-01T00:00:00Z","metric_kind":"wer","model_id":"whisperkit|whisper|tiny|default","peak_memory_gb":0.4,"rtf":0.1,"warmup_seconds":2}
        """
        let row = try iso8601Decoder().decode(MeasurementRow.self, from: Data(legacy.utf8))
        #expect(row.runKind == nil)
        // #118: nil means "the field was absent", NOT an enum case. A legacy row
        // makes no claim at all about how it was decoded.
        #expect(row.decodeDeterministic == nil)
    }

    @Test func `Measurement row round-trips the new fields preserving values`() throws {
        let row = row(.deterministicEnforced)
        let json = String(decoding: try iso8601Encoder().encode(row), as: UTF8.self)
        // snake_case keys on disk (spec: BCNF store field naming).
        #expect(json.contains("\"run_kind\""))
        #expect(json.contains("\"decode_deterministic\""))
        let decoded = try iso8601Decoder().decode(MeasurementRow.self, from: Data(json.utf8))
        #expect(decoded == row)
        #expect(decoded.runKind == "release-sweep")
        #expect(decoded.decodeDeterministic == .deterministicEnforced)
    }

    @Test func `Nil new fields encode as absent keys, mirroring hf_revision`() throws {
        // Default init leaves runKind / decodeDeterministic (and hfRevision) nil;
        // synthesized Codable omits nil optionals, so the keys never appear.
        // CROSS-REPO CONTRACT: the bench validator (bestASR-bench
        // tools/validate_measurements.py) accepts an ABSENT key as "legacy row";
        // an explicit null would be a schema violation.
        let row = MeasurementRow(
            modelId: "whisperkit|whisper|tiny|default", corpusId: "c", machineId: "m",
            measuredAt: Date(timeIntervalSince1970: 1_800_000_000), metricKind: .wer,
            errorRate: 0.1, rtf: 0.2, peakMemoryGB: 1, warmupSeconds: 1,
            appVersion: "0.4.0", macosVersion: "27.0")
        let json = String(decoding: try iso8601Encoder().encode(row), as: UTF8.self)
        #expect(!json.contains("run_kind"))
        #expect(!json.contains("decode_deterministic"))
        #expect(!json.contains("null"))
        #expect(!json.contains("hf_revision"))  // same omit-nil behavior we mirror
    }

    // MARK: DecodeDeterminism wire format (#118)

    @Test func `Each determinism case round-trips through its hyphenated wire string`() throws {
        let expected: [DecodeDeterminism: String] = [
            .deterministicEnforced: "deterministic-enforced",
            .fallbackEnabled: "fallback-enabled",
            .flagNotConsumed: "flag-not-consumed",
        ]
        for (value, wire) in expected {
            #expect(value.rawValue == wire)
            let json = String(decoding: try iso8601Encoder().encode(row(value)), as: UTF8.self)
            #expect(json.contains("\"decode_deterministic\":\"\(wire)\""))
            let decoded = try iso8601Decoder().decode(MeasurementRow.self, from: Data(json.utf8))
            #expect(decoded.decodeDeterministic == value)
        }
    }

    @Test func `Unknown decode_deterministic wire value fails the decode loudly`() throws {
        // Fail loud, not silently nil: an unrecognized condition must never be
        // read back as "legacy row" (that would launder an unknown claim into
        // "no claim"). Synthesized Codable throws DecodingError.dataCorrupted.
        let bogus = """
        {"app_version":"0.3.0","corpus_id":"c","decode_deterministic":"bogus","error_rate":0.2,"machine_id":"m","macos_version":"27.0","measured_at":"2026-01-01T00:00:00Z","metric_kind":"wer","model_id":"whisperkit|whisper|tiny|default","peak_memory_gb":0.4,"rtf":0.1,"warmup_seconds":2}
        """
        let error = #expect(throws: DecodingError.self) {
            try iso8601Decoder().decode(MeasurementRow.self, from: Data(bogus.utf8))
        }
        guard case .dataCorrupted? = error else {
            Issue.record("expected DecodingError.dataCorrupted, got \(String(describing: error))")
            return
        }

        // Contrast: an explicit null is NOT an unknown value — decodeIfPresent
        // reads it as absent, so a null-emitting encoder still round-trips as
        // "legacy row" rather than exploding (the read side is tolerant; our
        // WRITE side never emits null — see the absent-keys test above).
        let explicitNull = """
        {"app_version":"0.3.0","corpus_id":"c","decode_deterministic":null,"error_rate":0.2,"machine_id":"m","macos_version":"27.0","measured_at":"2026-01-01T00:00:00Z","metric_kind":"wer","model_id":"whisperkit|whisper|tiny|default","peak_memory_gb":0.4,"rtf":0.1,"warmup_seconds":2}
        """
        let row = try iso8601Decoder().decode(MeasurementRow.self, from: Data(explicitNull.utf8))
        #expect(row.decodeDeterministic == nil)
    }

    // MARK: The honest gate (#120 item 1)

    @Test func `Flag-consuming backends record what the flag actually did`() {
        #expect(
            DecodeDeterminism.forBackend(ModelGrid.backendWhisperKit, flagRequested: true)
                == .deterministicEnforced)
        #expect(
            DecodeDeterminism.forBackend(ModelGrid.backendWhisperKit, flagRequested: false)
                == .fallbackEnabled)
        #expect(
            DecodeDeterminism.forBackend(ModelGrid.backendWhisperCpp, flagRequested: true)
                == .deterministicEnforced)
        #expect(
            DecodeDeterminism.forBackend(ModelGrid.backendWhisperCpp, flagRequested: false)
                == .fallbackEnabled)
    }

    @Test func `Backends that ignore the flag never claim determinism`() {
        // NEVER LIE: mlx-audio's --decode-deterministic is a silent no-op and
        // the Fluid backends have no such knob, so a requested flag must NOT
        // become a determinism claim (#111/#118). flag-not-consumed makes no
        // claim about whether those decodes are in fact reproducible.
        for backend in [
            ModelGrid.backendMLXAudio, ModelGrid.backendFluidParakeet,
            ModelGrid.backendFluidParaformer, ModelGrid.backendFluidSenseVoice,
            "some-future-backend",
        ] {
            #expect(
                DecodeDeterminism.forBackend(backend, flagRequested: true) == .flagNotConsumed)
            #expect(
                DecodeDeterminism.forBackend(backend, flagRequested: false) == .flagNotConsumed)
        }
    }

    // MARK: SubmissionRow (denormalized publish row carries the same provenance)

    @Test func `Submission packaging threads the new provenance through`() throws {
        let row = MeasurementRow(
            modelId: "whisperkit|whisper|large-v3|default", corpusId: "abc123abc123",
            machineId: MachineRow.id(chip: "Apple M5 Max", unifiedMemoryGB: 128),
            measuredAt: Date(timeIntervalSince1970: 1_752_800_000), metricKind: .cer,
            errorRate: 0.12, rtf: 0.14, peakMemoryGB: 3.1, warmupSeconds: 8.0,
            appVersion: "0.14.0", macosVersion: "26.0",
            runKind: "release-sweep", decodeDeterministic: .deterministicEnforced)
        let submissions = SubmissionPackager.package(
            local: [row], machines: [MachineRow(chip: "Apple M5 Max", unifiedMemoryGB: 128)],
            canonicalCorpusIds: ["abc123abc123"], publishedKeys: [], contributor: "che")
        #expect(submissions.count == 1)
        #expect(submissions[0].runKind == "release-sweep")
        #expect(submissions[0].decodeDeterministic == .deterministicEnforced)

        // JSONL round-trips the snake_case keys.
        let jsonl = try SubmissionPackager.encodeJSONL(submissions)
        #expect(jsonl.contains("\"run_kind\""))
        #expect(jsonl.contains("\"decode_deterministic\":\"deterministic-enforced\""))
        let decoded = try iso8601Decoder().decode(
            SubmissionRow.self, from: Data(jsonl.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        #expect(decoded.runKind == "release-sweep")
        #expect(decoded.decodeDeterministic == .deterministicEnforced)
    }

    @Test func `Legacy submission JSON without the new keys decodes to nil`() throws {
        let legacy = """
        {"app_version":"0.14.0","chip":"Apple M5 Max","contributor":"che","corpus_id":"abc123abc123","error_rate":0.12,"machine_id":"deadbeefdead","macos_version":"26.0","measured_at":"2026-01-01T00:00:00Z","metric_kind":"cer","model_id":"whisperkit|whisper|large-v3|default","peak_memory_gb":3.1,"rtf":0.14,"unified_memory_gb":128,"warmup_seconds":8}
        """
        let row = try iso8601Decoder().decode(SubmissionRow.self, from: Data(legacy.utf8))
        #expect(row.runKind == nil)
        #expect(row.decodeDeterministic == nil)
    }

    // MARK: --run-kind value domain at the CLI boundary (#120 item 2)

    @Test func `Run-kind vocabulary is the single Swift-side source of truth`() {
        #expect(Set(RunKind.allCases.map(\.rawValue)) == ["release-sweep", "adhoc"])
        #expect(RunKind(rawValue: "bogus") == nil)
    }

    @Test func `Known run kinds parse and reach the core as their wire strings`() throws {
        let sweep = try Benchmark.parse(["a.wav", "--reference", "r.txt", "--run-kind", "release-sweep"])
        #expect(sweep.runKind == .releaseSweep)
        #expect(sweep.runKind?.rawValue == "release-sweep")
        let adhoc = try Benchmark.parse(["a.wav", "--reference", "r.txt", "--run-kind", "adhoc"])
        #expect(adhoc.runKind == .adhoc)
        // An omitted flag stays nil — "no provenance tag" is a valid state.
        let bare = try Benchmark.parse(["a.wav", "--reference", "r.txt"])
        #expect(bare.runKind == nil)
    }

    @Test func `Unknown run kind is rejected at the CLI boundary, not in bench CI`() {
        // Pre-#120 a typo travelled verbatim into the store and only failed in
        // the bench repo's CI — fail-loud at the wrong end.
        #expect(throws: (any Error).self) {
            try Benchmark.parse(["a.wav", "--reference", "r.txt", "--run-kind", "release_sweep"])
        }
        #expect(throws: (any Error).self) {
            try Benchmark.parse(["a.wav", "--reference", "r.txt", "--run-kind", "bogus"])
        }
    }

    // MARK: - the pre-#118 shape (#130 verify)

    @Test func `A pre-118 boolean decode_deterministic is rejected, not coerced`() throws {
        // #111 briefly wrote `decode_deterministic` as a JSON boolean before #118
        // settled on the enum. Nothing released ever emitted one and no row in
        // either repo carries one — but a census expires, and this does not.
        // Locking the behaviour states the choice: an old boolean is REJECTED
        // rather than migrated (true -> deterministic-enforced), because the
        // mapping would have to re-derive the backend to stay honest.
        for legacy in ["true", "false"] {
            let json = """
                {"model_id":"whisperkit|whisper|large-v3|default","corpus_id":"c1",
                 "machine_id":"m1","measured_at":"2026-07-30T00:00:00Z","metric_kind":"cer",
                 "error_rate":0.1,"rtf":0.5,"peak_memory_gb":1.0,"warmup_seconds":0.0,
                 "app_version":"0.16.0","macos_version":"27.0",
                 "decode_deterministic":\(legacy)}
                """
            #expect(throws: DecodingError.self) {
                _ = try self.iso8601Decoder().decode(MeasurementRow.self, from: Data(json.utf8))
            }
        }
    }

    @Test func `A submission row with no provenance omits the keys on the wire`() throws {
        // SubmissionRow is what actually crosses to the bench repo, so the
        // absent-not-null contract has to hold on THIS type, not only on
        // MeasurementRow — the bench validator treats null as absent now, but
        // the producer is still expected never to write one.
        let bare = MeasurementRow(
            modelId: "whisperkit|whisper|large-v3|default", corpusId: "abc123abc123",
            machineId: MachineRow.id(chip: "Apple M5 Max", unifiedMemoryGB: 128),
            measuredAt: Date(timeIntervalSince1970: 1_752_800_000), metricKind: .cer,
            errorRate: 0.12, rtf: 0.14, peakMemoryGB: 3.1, warmupSeconds: 8.0,
            appVersion: "0.14.0", macosVersion: "26.0")  // both provenance fields omitted
        let rows = SubmissionPackager.package(
            local: [bare], machines: [MachineRow(chip: "Apple M5 Max", unifiedMemoryGB: 128)],
            canonicalCorpusIds: ["abc123abc123"], publishedKeys: [], contributor: "tester")
        #expect(rows.count == 1)
        let jsonl = try SubmissionPackager.encodeJSONL(rows)
        #expect(!jsonl.contains("decode_deterministic"))
        #expect(!jsonl.contains("run_kind"))
        #expect(!jsonl.contains("null"))
    }
}
