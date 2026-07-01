import AVFoundation
import Foundation
import Testing
@testable import BestASRKit

struct SystemDetectorTests {
    func probe(
        arch: String = "arm64",
        translated: Bool = false,
        chip: String? = "Apple M5 Max",
        memoryBytes: UInt64 = 137_438_953_472,
        os: String = "27.0.0"
    ) -> SystemDetector.Probe {
        .init(
            machineArchitecture: arch,
            isTranslated: translated,
            chipName: chip,
            physicalMemoryBytes: memoryBytes,
            osVersion: os
        )
    }

    @Test func `Reports chip, unified memory, and macOS version on Apple Silicon`() throws {
        let info = try SystemDetector.detect(probe: probe())
        #expect(info.chip == "Apple M5 Max")
        #expect(info.unifiedMemoryGB > 0)
        #expect(info.macosVersion == "27.0.0")
        #expect(info.hasANE == true)
    }

    @Test func `Unknown chip generation degrades ANE to unknown without raising`() throws {
        let info = try SystemDetector.detect(probe: probe(chip: "Apple Z1 Ultra"))
        #expect(info.hasANE == nil)
    }

    @Test func `Non-Apple-Silicon host is rejected clearly`() {
        #expect(throws: BestASRError.self) {
            _ = try SystemDetector.detect(probe: probe(arch: "x86_64"))
        }
    }

    @Test func `Rosetta translation is rejected even when hardware is arm64`() {
        #expect(throws: BestASRError.self) {
            _ = try SystemDetector.detect(probe: probe(arch: "x86_64", translated: true))
        }
    }

    @Test func `Live detection on this machine yields a plausible profile`() throws {
        // This test suite only runs on Apple Silicon (platform requirement).
        let info = try SystemDetector.detect()
        #expect(info.chip.hasPrefix("Apple"))
        #expect(info.unifiedMemoryGB > 1)
    }
}

struct LanguageResolverTests {
    @Test func `Explicit language is used verbatim`() {
        #expect(LanguageResolver.resolve("zh") == "zh")
        #expect(LanguageResolver.resolve("ZH-TW") == "zh-tw")
    }

    @Test func `Auto and empty defer to the engine as nil`() {
        #expect(LanguageResolver.resolve("auto") == nil)
        #expect(LanguageResolver.resolve("") == nil)
        #expect(LanguageResolver.resolve(nil) == nil)
    }

    @Test(arguments: [("zh", MetricKind.cer), ("zh-tw", .cer), ("ja", .cer), ("ko", .cer), ("en", .wer), ("de", .wer)])
    func `Metric kind follows the language`(language: String, expected: MetricKind) {
        #expect(LanguageResolver.metricKind(forLanguage: language) == expected)
    }

    @Test func `Auto metric inference reads the reference text`() {
        #expect(LanguageResolver.metricKind(inferredFromReference: "今天天氣好") == .cer)
        #expect(LanguageResolver.metricKind(inferredFromReference: "the cat sat down") == .wer)
    }
}

struct AudioProberTests {
    /// Writes a real 16 kHz mono wav so AVFoundation has something to read.
    func makeWav(in dir: URL, seconds: Double = 1.0) throws -> String {
        let url = dir.appendingPathComponent("clip.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(16000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url.path
    }

    @Test func `Probing a valid audio file fills duration, format, rate, and channels`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try makeWav(in: dir, seconds: 2.0)
        let info = try AudioProber.probe(path: path, requestedLanguage: "zh")
        #expect(info.duration != nil)
        #expect(abs((info.duration ?? 0) - 2.0) < 0.05)
        #expect(info.format == "wav")
        #expect(info.sampleRate == 16000)
        #expect(info.channels == 1)
        #expect(info.language == "zh")
    }

    @Test func `Missing audio file is a clear usage error`() {
        #expect(throws: BestASRError.usage("audio file not found: /nonexistent/clip.wav")) {
            _ = try AudioProber.probe(path: "/nonexistent/clip.wav")
        }
    }

    @Test func `Non-audio file is rejected naming the file`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("not-audio.wav").path
        try "this is not audio".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(throws: BestASRError.self) {
            _ = try AudioProber.probe(path: path)
        }
    }
}
