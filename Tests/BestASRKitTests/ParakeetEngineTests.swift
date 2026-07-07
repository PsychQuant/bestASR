import Foundation
import Testing
@testable import BestASRKit

/// ParakeetEngine contract (#35, spec parakeet-engine): the third Engine
/// conformer, backed by FluidAudio's Parakeet TDT CoreML models. Tests use
/// the injectable pipeline seam (same discipline as WhisperKitEngine #9) so
/// no CoreML model ever loads here.
struct ParakeetEngineTests {
    let options = TranscribeOptions(model: "0.6b-v3", quantization: "default", language: "en")

    /// Spy pipeline standing in for the FluidAudio-backed adapter.
    struct SpyPipeline: ParakeetTranscribing {
        let result: @Sendable (String, String?) throws -> ParakeetOutput

        func transcribe(audioPath: String, language: String?) async throws -> ParakeetOutput {
            try result(audioPath, language)
        }
    }

    @Test func `Engine identifies as the fluid-parakeet backend and is available`() async {
        let engine = ParakeetEngine()
        #expect(engine.id == .fluidParakeet)
        #expect(await engine.isAvailable() == true)
    }

    @Test func `FluidAudio output maps onto raw segments with timings and confidence`() async throws {
        let engine = ParakeetEngine(pipelineFactory: { _ in
            SpyPipeline { _, _ in
                ParakeetOutput(
                    text: "hello world again",
                    confidence: 0.9,
                    duration: 3.0,
                    tokenTimings: [
                        .init(token: "hello", startTime: 0.0, endTime: 0.5),
                        .init(token: " world", startTime: 0.5, endTime: 1.0),
                        // A gap far beyond the segment-break threshold splits
                        // the transcript into a second raw segment.
                        .init(token: " again", startTime: 2.4, endTime: 3.0),
                    ]
                )
            }
        })
        let raw = try await engine.transcribeRaw(audioPath: "clip.wav", options: options)

        try #require(raw.segments.count == 2)
        #expect(raw.segments[0].text == "hello world")
        #expect(raw.segments[0].start == 0.0)
        #expect(raw.segments[0].end == 1.0)
        // Leading space on segments after the first is the seam contract
        // (Engine.transcribe joins with no separator — verify H1).
        #expect(raw.segments[1].text == " again")
        #expect(raw.segments[1].start == 2.4)
        #expect(raw.segments[1].end == 3.0)
        #expect(raw.duration == 3.0)
        // Whole-result confidence flows onto every segment (Parakeet reports
        // one confidence per transcription, not per segment).
        #expect(raw.segments.allSatisfy { $0.confidence.map { $0 > 0.8 } ?? false })
    }

    @Test func `Multi-segment transcripts keep word boundaries through the seam join`() async throws {
        // Verify H1 (#35): Engine.transcribe joins segment texts with NO
        // separator — the seam contract is that every segment from the second
        // on carries its own leading space (WhisperKit does; EngineTests locks
        // it). A trimming mapper glues words across every >0.8s pause and
        // systematically inflates measured WER for this family only.
        let engine = ParakeetEngine(pipelineFactory: { _ in
            SpyPipeline { _, _ in
                ParakeetOutput(
                    text: "hello world again",
                    confidence: 0.9,
                    duration: 3.0,
                    tokenTimings: [
                        .init(token: "hello", startTime: 0.0, endTime: 0.5),
                        .init(token: " world", startTime: 0.5, endTime: 1.0),
                        .init(token: " again", startTime: 2.4, endTime: 3.0),
                    ]
                )
            }
        })
        let transcript = try await engine.transcribe(
            audioPath: "clip.wav", options: options)
        #expect(transcript.text == "hello world again")
    }

    @Test func `Timings that reconstruct to nothing fall back to the full text`() async throws {
        // Verify M1 (#35): non-empty tokenTimings whose tokens are all
        // whitespace must not silently drop output.text.
        let engine = ParakeetEngine(pipelineFactory: { _ in
            SpyPipeline { _, _ in
                ParakeetOutput(
                    text: "real text survives",
                    confidence: 0.8,
                    duration: 2.0,
                    tokenTimings: [
                        .init(token: " ", startTime: 0.0, endTime: 0.5),
                        .init(token: "  ", startTime: 0.5, endTime: 1.0),
                    ]
                )
            }
        })
        let raw = try await engine.transcribeRaw(audioPath: "clip.wav", options: options)
        try #require(raw.segments.count == 1)
        #expect(raw.segments[0].text == "real text survives")
        #expect(raw.segments[0].end == 2.0)
    }

    @Test func `Hostile timings are clamped and ordered, never crashing the mapper`() async throws {
        // #53 item 2: out-of-order, negative, and past-duration timings from
        // a misbehaving pipeline are defended at the seam — sorted, clamped
        // to 0...duration — and text is never dropped.
        let engine = ParakeetEngine(pipelineFactory: { _ in
            SpyPipeline { _, _ in
                ParakeetOutput(
                    text: "b a c",
                    confidence: 0.9,
                    duration: 3.0,
                    tokenTimings: [
                        .init(token: " a", startTime: 1.0, endTime: 1.4),  // out of order
                        .init(token: "b", startTime: -0.5, endTime: 0.4),  // negative start
                        .init(token: " c", startTime: 2.9, endTime: 9.0),  // end past duration
                    ]
                )
            }
        })
        let raw = try await engine.transcribeRaw(audioPath: "clip.wav", options: options)
        #expect(raw.segments.allSatisfy { $0.start >= 0 && $0.end <= 3.0 && $0.start <= $0.end })
        let joined = raw.segments.map(\.text).joined()
        #expect(joined.contains("b") && joined.contains("a") && joined.contains("c"))
        #expect(raw.segments.first?.text.hasPrefix("b") == true)  // order restored
    }

    @Test func `All-invalid timings fall back to the full text`() async throws {
        // end < start on every pair → no valid timing survives → full-text
        // fallback, never an empty transcript.
        let engine = ParakeetEngine(pipelineFactory: { _ in
            SpyPipeline { _, _ in
                ParakeetOutput(
                    text: "survives intact",
                    confidence: 0.9,
                    duration: 2.0,
                    tokenTimings: [
                        .init(token: "x", startTime: 1.5, endTime: 0.5),
                        .init(token: "y", startTime: 1.9, endTime: 1.0),
                    ]
                )
            }
        })
        let raw = try await engine.transcribeRaw(audioPath: "clip.wav", options: options)
        try #require(raw.segments.count == 1)
        #expect(raw.segments[0].text == "survives intact")
    }

    @Test func `One inverted pair distrusts the whole batch, keeping all text`() async throws {
        // Dropping just the inverted token would drop its TEXT — the seam
        // must instead distrust the batch and fall back to the full text.
        let engine = ParakeetEngine(pipelineFactory: { _ in
            SpyPipeline { _, _ in
                ParakeetOutput(
                    text: "alpha beta gamma",
                    confidence: 0.9,
                    duration: 3.0,
                    tokenTimings: [
                        .init(token: "alpha", startTime: 0.0, endTime: 0.5),
                        .init(token: " beta", startTime: 1.5, endTime: 0.9),  // inverted
                        .init(token: " gamma", startTime: 2.0, endTime: 2.5),
                    ]
                )
            }
        })
        let raw = try await engine.transcribeRaw(audioPath: "clip.wav", options: options)
        try #require(raw.segments.count == 1)
        #expect(raw.segments[0].text == "alpha beta gamma")
    }

    @Test func `Missing token timings degrade to a single full-text segment`() async throws {
        let engine = ParakeetEngine(pipelineFactory: { _ in
            SpyPipeline { _, _ in
                ParakeetOutput(
                    text: "no timings here", confidence: 0.7, duration: 2.0, tokenTimings: nil)
            }
        })
        let raw = try await engine.transcribeRaw(audioPath: "clip.wav", options: options)

        try #require(raw.segments.count == 1)
        #expect(raw.segments[0].text == "no timings here")
        #expect(raw.segments[0].start == 0.0)
        #expect(raw.segments[0].end == 2.0)
    }

    @Test func `Model loading failure surfaces as a typed TranscriptionError`() async {
        struct DownloadFailed: Error, LocalizedError {
            var errorDescription: String? { "model download failed" }
        }
        let engine = ParakeetEngine(pipelineFactory: { _ in throw DownloadFailed() })

        do {
            _ = try await engine.transcribeRaw(audioPath: "clip.wav", options: options)
            Issue.record("expected transcribeRaw to throw")
        } catch let error as TranscriptionError {
            #expect(error.backend == "fluid-parakeet")
            #expect(error.message.contains("model download failed"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func `Pipeline is created once per model and reused`() async throws {
        // CreateOnceStore discipline (#7): the factory must run once for the
        // same cache key across consecutive transcriptions.
        actor Counter {
            var value = 0
            func bump() -> Int { value += 1; return value }
        }
        let counter = Counter()
        let engine = ParakeetEngine(pipelineFactory: { _ in
            _ = await counter.bump()
            return SpyPipeline { _, _ in
                ParakeetOutput(text: "x", confidence: 1, duration: 1, tokenTimings: nil)
            }
        })
        _ = try await engine.transcribeRaw(audioPath: "a.wav", options: options)
        _ = try await engine.transcribeRaw(audioPath: "b.wav", options: options)
        #expect(await counter.value == 1)
    }

    // MARK: - #69 duration=0 fallback (FluidAudio 0.15.4 returns duration 0)

    @Test func `Zero upstream duration falls back to the timings' max end`() async throws {
        let engine = ParakeetEngine(pipelineFactory: { _ in
            SpyPipeline(result: { _, _ in ParakeetOutput(
                text: "hello world", confidence: 0.9, duration: 0,
                tokenTimings: [
                    .init(token: "hello", startTime: 0.2, endTime: 1.1),
                    .init(token: " world", startTime: 1.3, endTime: 2.4),
                ]) })
        })
        let raw = try await engine.transcribeRaw(
            audioPath: "missing.wav",
            options: TranscribeOptions(model: "0.6b-v3", quantization: "default"))
        #expect(raw.duration == 2.4)  // Optional == literal works  // timings survive, not clamped to a 0-point
        #expect(raw.segments.contains { $0.end > 0 })
    }

    @Test func `Zero duration with no timings falls back to the probed audio length`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = try makeWavFile(in: dir, seconds: 3)
        let engine = ParakeetEngine(pipelineFactory: { _ in
            SpyPipeline(result: { _, _ in ParakeetOutput(
                text: "hello", confidence: 0.9, duration: 0, tokenTimings: nil) })
        })
        let raw = try await engine.transcribeRaw(
            audioPath: wav,
            options: TranscribeOptions(model: "0.6b-v3", quantization: "default"))
        #expect(abs((raw.duration ?? 0) - 3.0) < 0.1)  // probed, not 0
        #expect(raw.segments.first?.end ?? 0 > 0)  // SRT cue is no longer 0 --> 0
    }

}
