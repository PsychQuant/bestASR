import Foundation
import Testing

@testable import BestASRKit

/// Task 2.1 of change `model-identity-structured` (issue #183).
///
/// `ModelRow` now holds a `ModelID` and a `Quantization` instead of four loose
/// strings. Nothing on disk may notice: the store's key stays
/// `runtime|family|size|quantization`, and the row's JSON stays flat.
///
/// The fixture is the committed `docs/model-identity-audit.csv` rather than
/// `~/.bestasr/store/models.jsonl`. A home-directory file is absent wherever
/// this runs but this machine, and a round-trip assertion over zero rows passes
/// — which is indistinguishable from a working codec. The live store is checked
/// too, but only as a second opinion.
struct ModelRowCodecTests {

    /// The package root, located from this file rather than the process's
    /// working directory, which `swift test` does not promise.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)  // Tests/BestASRKitTests/<this>.swift
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The `model_id` column of the committed audit snapshot.
    private static func fixtureModelIDs() throws -> [String] {
        let url = repoRoot.appending(path: "docs/model-identity-audit.csv")
        #expect(FileManager.default.fileExists(atPath: url.path), "no fixture at \(url.path)")
        let text = try String(contentsOf: url, encoding: .utf8)
        // Split on newline *semantics*, not on a byte: the file is written by
        // `csv.writer`, whose default terminator is CRLF, and Swift reads
        // "\r\n" as one Character that does not equal "\n". Splitting on "\n"
        // returns the whole file as a single line, and every assertion below
        // then passes over nothing.
        var lines = text.split(whereSeparator: \.isNewline)
        #expect(lines.count > 1, "fixture has \(lines.count) lines, \(text.count) chars")
        let header = lines.removeFirst().split(separator: ",").map(String.init)
        let column = try #require(header.firstIndex(of: "model_id"))
        // `model_id` is the first column and contains no comma or quote, so a
        // plain split is exact here. Asserting the index keeps that true if the
        // column ever moves.
        #expect(column == 0)
        return lines.map { String($0.split(separator: ",")[column]) }
    }

    @Test func `every stored model_id re-serialises byte for byte`() throws {
        let stored = try Self.fixtureModelIDs()

        // Non-vacuity: a codec test over an empty list is green and worthless.
        #expect(!stored.isEmpty)
        let segments = stored.map { $0.split(separator: "|", omittingEmptySubsequences: false) }
        #expect(segments.contains { $0[2] == ModelID.removedPlaceholder[...] },
                "fixture no longer exercises a placeholder size")
        #expect(segments.contains { $0[3] == ModelID.removedPlaceholder[...] },
                "fixture no longer exercises a placeholder quantization")

        // Round-4 verify C7: this loop used to split a string on "|" and join
        // it back with "|", which is an identity function — it never
        // constructed or decoded a `ModelRow`, the thing whose codec the test
        // claims to check. It now goes through the real one.
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        for id in stored {
            let parts = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            #expect(parts.count == 4, "not a four-segment key: \(id)")
            let json = """
                {"model_id":"\(id)","backend":"\(parts[0])","family":"\(parts[1])",                "size":"\(parts[2])","quantization":"\(parts[3])","languages":["multi"],                "est_memory_gb":1.0,"priority":1,"verified":false}
                """
            let row = try decoder.decode(ModelRow.self, from: Data(json.utf8))
            #expect(row.modelId == id, "decoded row rebuilt a different key")
            // And re-encoding it reproduces the same key on the wire.
            let round = try #require(
                try JSONSerialization.jsonObject(with: encoder.encode(row)) as? [String: Any])
            #expect(round["model_id"] as? String == id)
        }
    }

    @Test func `the live store agrees with the committed snapshot`() throws {
        let store = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: ".bestasr/store/models.jsonl")
        guard FileManager.default.fileExists(atPath: store.path) else { return }

        let live = try String(contentsOf: store, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> String? in
                let object = try? JSONSerialization.jsonObject(with: Data(line.utf8))
                return (object as? [String: Any])?["model_id"] as? String
            }
        #expect(!live.isEmpty)
        for id in live {
            let parts = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            #expect(parts.count == 4, "not a four-segment key: \(id)")
            #expect(ModelRow.id(backend: parts[0], family: parts[1],
                                size: parts[2], quantization: parts[3]) == id)
        }
    }

    @Test func `a row's JSON keeps its flat columns`() throws {
        let identity = try #require(ModelID(family: "whisper", size: "large-v3-turbo"))
        let row = ModelRow(
            backend: "whisperkit", identity: identity, quantization: .deferred(.runtime),
            estMemoryGB: 1.6, priority: 1)

        let json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(row))
                as? [String: Any])
        // The store reads these three as top-level strings. Holding a `ModelID`
        // must not push them into a nested object.
        #expect(json["family"] as? String == "whisper")
        #expect(json["size"] as? String == "large-v3-turbo")
        #expect(json["quantization"] as? String == Quantization.deferred(.runtime).serialised)
        #expect(json["model_id"] as? String == row.modelId)

        let decoded = try JSONDecoder().decode(ModelRow.self, from: JSONEncoder().encode(row))
        #expect(decoded == row)
        #expect(decoded.identity == identity)
        #expect(decoded.quantization == .deferred(.runtime))
    }

    @Test func `a row rejects a stored record whose family is missing`() {
        let corrupt = #"{"model_id":"whisperkit||small|q8","backend":"whisperkit","family":"","#
            + #""size":"small","quantization":"q8","languages":["multi"],"#
            + #""est_memory_gb":1.0,"priority":1,"verified":false}"#
        // An empty family is not an incomplete identity, it is a corrupt one.
        // Decoding must say so rather than yield a row that identifies nothing.
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ModelRow.self, from: Data(corrupt.utf8))
        }
    }
}

/// Task 4.1 of change `model-identity-structured` (issue #183).
///
/// `StoreProjection` used to downgrade the store's four-segment identity to
/// fit an address grammar that varied by runtime, discarding the family from
/// every non-mlx record. It no longer branches on who ships the runtime.
struct StoreProjectionIdentityTests {

    private func snapshot(modelId: String) -> BenchmarkStore.Snapshot {
        let corpus = CorpusRow(
            name: "c", language: "en", audioSHA256: String(repeating: "c", count: 64),
            referenceSHA256: "", duration: 30, audioPath: "", referencePath: "")
        return BenchmarkStore.Snapshot(
            machines: [], models: [], corpora: [corpus],
            measurements: [MeasurementRow(
                modelId: modelId, corpusId: corpus.corpusId, machineId: "h",
                measuredAt: Date(timeIntervalSince1970: 1_000), metricKind: .wer,
                errorRate: 0.1, rtf: 0.1, peakMemoryGB: 1, warmupSeconds: 1,
                appVersion: "0.3.0", macosVersion: "27.0")],
            warnings: [])
    }

    @Test func `A non-mlx record keeps the family the stored key gave it`() throws {
        // Today this family survives only because the legacy patch puts it
        // back; before #183 the projection dropped it for every backend whose
        // name was not mlx-audio.
        let record = try #require(
            snapshot(modelId: "whisperkit|whisper|small|deferred:runtime")
                .projectedRecords().first)
        #expect(record.identity == ModelID(family: "whisper", size: "small"))
        #expect(record.identity?.family == "whisper")
        // Unambiguous under this runtime, so the address stays the bare size —
        // which is what `--model small` matches against.
        #expect(record.model == "whisper/small")
        #expect(record.identityComplete)
    }

    @Test func `An ambiguous size keeps its family in the address too`() throws {
        // canary 1b and mms 1b both exist, so `1b` alone would name neither.
        let record = try #require(
            snapshot(modelId: "mlx-audio|canary|1b|q8").projectedRecords().first)
        #expect(record.identity == ModelID(family: "canary", size: "1b"))
        #expect(record.model == "canary/1b")
    }

    @Test func `A record whose quantization is unrecorded is marked, not dropped`() throws {
        let record = try #require(
            snapshot(modelId: "mlx-audio|mms|1b|unknown").projectedRecords().first)
        #expect(record.identity == ModelID(family: "mms", size: "1b"))
        #expect(record.identityComplete == false)
    }

    @Test func `A legacy id whose family repeats its size still reads as whisper`() throws {
        // Four such ids are in the store (whisperkit|base|base|default and
        // friends). Dropping the normalisation would split their history from
        // re-benchmarks of the same candidate.
        let record = try #require(
            snapshot(modelId: "whisperkit|base|base|default").projectedRecords().first)
        #expect(record.identity == ModelID(family: "whisper", size: "base"))
        #expect(record.model == "whisper/base")
    }
}

extension StoreProjectionIdentityTests {
}

/// The acceptance criterion for read-time canonicalisation (#183, round 6 →
/// option 1). The catalog now carries true values, so its keys deliberately
/// DIFFER from what is on disk. What must hold instead — and it is the
/// stronger claim — is that every stored key still resolves to a model the
/// catalog holds, so no measurement is orphaned by the rotation.
struct CatalogCanonicalisationTests {
    private static func storedKeys() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "docs/model-identity-audit.csv")
        var lines = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
        lines.removeFirst()
        return lines.map { String($0.split(separator: ",")[0]) }
    }

    @Test func `Every stored key resolves to a model the catalog holds`() throws {
        let stored = try Self.storedKeys()
        #expect(stored.count == 37)
        var orphaned: [String] = []
        for key in stored {
            let p = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let canon = ModelGrid.canonical(
                    backend: p[0], family: p[1], size: p[2], quantization: p[3]),
                  !ModelGrid.rows(backend: p[0], identity: canon.identity).isEmpty
            else { orphaned.append(key); continue }
        }
        #expect(orphaned.isEmpty, "stored keys the catalog can no longer place: \(orphaned)")
    }

    @Test func `A rotated key and its replacement name one candidate`() throws {
        // The round-4 CRITICAL, inverted into a guard: the 140 measurements
        // stored as `…|default` and every new one written as
        // `…|deferred:runtime` must collapse, not compete.
        let old = try #require(ModelGrid.canonical(
            backend: "whisperkit", family: "whisper", size: "large-v3-turbo",
            quantization: ModelID.removedPlaceholder))
        let new = try #require(ModelGrid.canonical(
            backend: "whisperkit", family: "whisper", size: "large-v3-turbo",
            quantization: Quantization.deferred(.runtime).serialised))
        #expect(old.identity == new.identity)
        #expect(old.quantization == new.quantization)
    }
}
