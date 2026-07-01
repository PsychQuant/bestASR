import Foundation
@testable import BestASRKit

/// Injectable stand-in engine so router/benchmark/CLI tests never touch a real
/// backend (design D11). Immutable + Sendable — safe under Swift Testing's
/// parallel execution.
struct MockEngine: Engine {
    let id: BackendID
    let available: Bool
    let raw: @Sendable (String, TranscribeOptions) throws -> RawTranscription

    func isAvailable() async -> Bool { available }

    func transcribeRaw(audioPath: String, options: TranscribeOptions) async throws -> RawTranscription {
        try raw(audioPath, options)
    }

    /// Engine that always yields the same segments.
    static func fixed(
        _ id: BackendID,
        available: Bool = true,
        segments: [RawTranscription.RawSegment] = [
            .init(start: 0.0, end: 2.5, text: "hello world")
        ],
        language: String? = "en",
        duration: Double? = 2.5
    ) -> MockEngine {
        MockEngine(id: id, available: available) { _, _ in
            RawTranscription(segments: segments, language: language, duration: duration)
        }
    }

    /// Engine whose transcription always fails with a plain (untyped) error.
    static func failing(_ id: BackendID, message: String = "decode error") -> MockEngine {
        MockEngine(id: id, available: true) { _, _ in
            throw NSError(
                domain: "MockEngine", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}

/// A unique temporary directory per call — parallel-test safe.
func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bestasr-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Host fixtures mirroring the machines the spec scenarios talk about.
enum Fixtures {
    static let m5Max = SystemInfo(
        chip: "Apple M5 Max", unifiedMemoryGB: 137.4, hasANE: true, macosVersion: "27.0"
    )

    static let smallMac = SystemInfo(
        chip: "Apple M2", unifiedMemoryGB: 8.0, hasANE: true, macosVersion: "14.5"
    )

    static func record(
        backend: BackendID = .whisperKit,
        model: String = "large-v3-turbo",
        quantization: String = "default",
        language: String = "zh",
        metricKind: MetricKind = .cer,
        errorRate: Double = 0.05,
        timesRealtime: Double = 12.0,
        chip: String = m5Max.chip
    ) -> BenchmarkRecord {
        BenchmarkRecord(
            backend: backend.rawValue,
            model: model,
            quantization: quantization,
            language: language,
            metricKind: metricKind,
            errorRate: errorRate,
            rtf: timesRealtime > 0 ? 1.0 / timesRealtime : 0,
            peakMemoryGB: 3.0,
            audioDuration: 60,
            measuredAt: Date(timeIntervalSince1970: 1_780_000_000),
            chip: chip,
            macosVersion: "27.0",
            appVersion: BestASRVersion.current
        )
    }
}
