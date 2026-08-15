import AVFoundation
import Foundation
@testable import BestASRKit

/// Injectable stand-in engine so router/benchmark/CLI tests never touch a real
/// backend (design D11). Immutable + Sendable — safe under Swift Testing's
/// parallel execution.
struct MockEngine: Engine {
    let id: BackendID
    let available: Bool
    /// Declared like any other engine — the protocol requirement has no default
    /// (design D2), and a test double is exactly where a silent default would
    /// hide a wrong assumption. `var` with a default keeps every existing
    /// call site working while letting a test drive the supported branch.
    var promptCapability: PromptCapability = .unsupported
    let raw: @Sendable (String, TranscribeOptions) throws -> RawTranscription

    func isAvailable() async -> Bool { available }

    func transcribeRaw(audioPath: String, options: TranscribeOptions) async throws -> RawTranscription {
        try raw(audioPath, options)
    }

    /// Engine that always yields the same segments.
    static func fixed(
        _ id: BackendID,
        available: Bool = true,
        promptCapability: PromptCapability = .unsupported,
        segments: [RawTranscription.RawSegment] = [
            .init(start: 0.0, end: 2.5, text: "hello world")
        ],
        language: String? = "en",
        duration: Double? = 2.5
    ) -> MockEngine {
        MockEngine(id: id, available: available, promptCapability: promptCapability) { _, _ in
            RawTranscription(segments: segments, language: language, duration: duration)
        }
    }

    /// `fixed`, but the options survive the call.
    ///
    /// Use this wherever a test cares WHAT the engine was asked to load, not
    /// just that it answered.
    static func spying(
        _ id: BackendID,
        into spy: OptionsSpy,
        available: Bool = true,
        promptCapability: PromptCapability = .unsupported,
        segments: [RawTranscription.RawSegment] = [
            .init(start: 0.0, end: 2.5, text: "hello world")
        ],
        language: String? = "en",
        duration: Double? = 2.5
    ) -> MockEngine {
        MockEngine(id: id, available: available, promptCapability: promptCapability) { _, options in
            spy.record(options)
            return RawTranscription(segments: segments, language: language, duration: duration)
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

extension ModelGrid.Resolution {
    /// TEST-ONLY. The identity, or nil for either non-resolving outcome.
    ///
    /// This is the collapse `ModelGrid.identity` stopped doing, kept available
    /// where a test's whole claim is "this resolves to X" and the two ways of
    /// not resolving are equally a failure of that claim. It lives in the test
    /// target so production code cannot reach it: there, the difference
    /// between "names nothing" and "names several" always matters.
    var resolvedIdentity: ModelID? {
        if case .resolved(let identity) = self { return identity }
        return nil
    }
}

/// Deterministic clock for anything that measures elapsed time.
///
/// Shared rather than file-private: the engine-seam tests drive the same two
/// command paths the CLI tests do, and a second private copy would be one more
/// place for the two to drift.
enum FakeClockProbe {
    static func probe() -> MeasurementProbe {
        let clock = FakeClock(step: 1.0)
        return clock.probe()
    }
}

/// Records every `TranscribeOptions` an engine is handed.
///
/// `MockEngine.fixed` discards its options, and for eight rounds no test could
/// observe what any code path actually asked an engine to load. That is why
/// round 8 could install a model-name translation at ONE of its two call sites
/// and still see 552 tests pass: the omission was not merely unasserted, it was
/// unobservable. What no test can see, no test can hold.
///
/// Locked rather than actor-isolated so the engine's `@Sendable` synchronous
/// closure can write to it without the seam becoming async.
final class OptionsSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TranscribeOptions] = []

    var seen: [TranscribeOptions] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// The model string each call carried, in call order.
    var models: [String] { seen.map(\.model) }

    func record(_ options: TranscribeOptions) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(options)
    }
}

/// A unique temporary directory per call — parallel-test safe.
func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bestasr-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a real wav so AVFoundation has something to read. Defaults to the
/// 16 kHz mono the engines expect; other rates/channel counts exercise the
/// AudioNormalizer conversion path (#36). `toneHz` fills the buffer with a
/// sine wave instead of silence so tests can assert content fidelity — a
/// resampler that zeroes samples passes duration checks but not this.
func makeWavFile(
    in dir: URL,
    seconds: Double = 1.0,
    name: String = "clip.wav",
    sampleRate: Double = 16000,
    channels: AVAudioChannelCount = 1,
    toneHz: Double? = nil
) throws -> String {
    let url = dir.appendingPathComponent(name)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(sampleRate * seconds)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    if let toneHz, let channelData = buffer.floatChannelData {
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) {
                channelData[channel][frame] =
                    sinf(Float(2.0 * .pi * toneHz * Double(frame) / sampleRate)) * 0.5
            }
        }
    }
    try file.write(from: buffer)
    return url.path
}

/// Host fixtures mirroring the machines the spec scenarios talk about.
enum Fixtures {
    static let m5Max = SystemInfo(
        chip: "Apple M5 Max", unifiedMemoryGB: 137.4, hasANE: true, macosVersion: "27.0"
    )

    static let smallMac = SystemInfo(
        chip: "Apple M2", unifiedMemoryGB: 8.0, hasANE: true, macosVersion: "14.5"
    )

    /// A record in the shape the projection actually produces.
    ///
    /// The convergence condition round 8's verify asked for. This used to take
    /// `model: String`, so every one of its 36 call sites spelled a model the
    /// way the code did BEFORE #183 — and rounds 7 and 8 could break the
    /// measured paths with 552 tests still green, because no fixture had ever
    /// carried a post-change shape.
    ///
    /// Family and size are separate arguments on purpose: an address cannot be
    /// handed in, so a spelling production never produces is not merely wrong
    /// here, it is unwritable. What the record carries — address, canonical
    /// quantization, identity — comes from `ModelGrid.canonical`, the same
    /// function `StoreProjection` reads through.
    static func record(
        backend: BackendID = .whisperKit,
        family: String = "whisper",
        size: String = "large-v3-turbo",
        quantization: String = ModelID.removedPlaceholder,
        language: String = "zh",
        metricKind: MetricKind = .cer,
        errorRate: Double = 0.05,
        timesRealtime: Double = 12.0,
        chip: String = m5Max.chip
    ) -> BenchmarkRecord {
        guard let canonical = ModelGrid.canonical(
            backend: backend.rawValue, family: family, size: size, quantization: quantization)
        else {
            // Not a test failure to report and continue from: every later
            // assertion would be about a record that names no model.
            fatalError("fixture names no model: \(backend.rawValue)|\(family)|\(size)")
        }
        return BenchmarkRecord(
            backend: backend.rawValue,
            model: ModelGrid.address(for: canonical.identity),
            quantization: canonical.quantization.serialised,
            identity: canonical.identity,
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

extension ModelID {
    /// TEST-ONLY constructors. Force-unwrapped on purpose: a fixture that
    /// names no model is a defect in the fixture, and crashing at the line
    /// that wrote it beats a `nil` travelling into an assertion.
    static func whisper(_ size: String) -> ModelID { ModelID(family: "whisper", size: size)! }
    static func of(_ family: String, _ size: String) -> ModelID {
        ModelID(family: family, size: size)!
    }
}

extension Fixtures {
    /// Options in the shape a measured path actually hands an engine.
    ///
    /// The engine-layer counterpart of `Fixtures.record`, and the gap round 9's
    /// devil's advocate found: engine tests spelled the model as a bare size —
    /// a string the Router has not produced since #183 — so
    /// `ModelGrid.engineName` was the IDENTITY FUNCTION in every one of them,
    /// and deleting an engine's translation changed nothing anywhere. All 564
    /// tests passed with three of the five engines no longer translating.
    ///
    /// Family and size are separate arguments for the same reason as `record`:
    /// the address is derived, never handed in, so a spelling production does
    /// not produce cannot be written here.
    static func engineOptions(
        backend: BackendID,
        family: String,
        size: String,
        quantization: String = ModelID.removedPlaceholder,
        language: String? = nil,
        prompt: String? = nil,
        deterministicDecode: Bool = false
    ) -> TranscribeOptions {
        guard let canonical = ModelGrid.canonical(
            backend: backend.rawValue, family: family, size: size, quantization: quantization)
        else {
            fatalError("fixture names no model: \(backend.rawValue)|\(family)|\(size)")
        }
        return TranscribeOptions(
            model: ModelGrid.address(for: canonical.identity),
            quantization: canonical.quantization.serialised,
            language: language, prompt: prompt,
            deterministicDecode: deterministicDecode)
    }
}

/// Records the model string a pipeline factory is handed.
///
/// An engine's translation is only observable at the point it loads a model,
/// and every fluid-family test discarded that argument (`pipelineFactory:
/// { _ in ... }`). Nothing could see whether the engine translated.
final class FactorySpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var seen: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ model: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(model)
    }
}
