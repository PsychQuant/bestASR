import AVFoundation
import Foundation

/// Converts arbitrary input audio to the 16 kHz mono PCM the ASR engines
/// expect (#36). WhisperKit's own resample path corrupts long compressed
/// files (87-minute mp3 → near-silent PCM, "（音樂）" transcript, exit 0);
/// normalizing at the engine seam guarantees every backend only ever sees
/// the format whose direct-read path is known-good.
public enum AudioNormalizer {
    public static let targetSampleRate: Double = 16000
    public static let targetChannelCount: AVAudioChannelCount = 1

    /// Read/convert chunk size in frames — bounds peak memory regardless of
    /// input length (an 87-minute file streams through a few MB of buffers,
    /// never a whole-file allocation).
    static let chunkFrames: AVAudioFrameCount = 65536

    /// Raised when a conversion that should succeed fails midway — surfaced,
    /// never swallowed (#36 fail-loud requirement).
    public struct NormalizationError: Error, LocalizedError {
        public let message: String

        public init(message: String) {
            self.message = message
        }

        public var errorDescription: String? {
            "audio normalization failed: \(message)"
        }
    }

    /// Engine-facing result. `cleanup()` removes the temporary file when one
    /// was created and is a no-op for passthrough.
    public struct NormalizedAudio: Sendable {
        public let path: String
        public let isTemporary: Bool

        public func cleanup() {
            guard isTemporary else { return }
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Returns the original path when the file is already 16 kHz mono — or
    /// when it cannot even be probed: unreadable input passes through so the
    /// engine keeps its established error surface (the CLI fail-louds
    /// unreadable files earlier via AudioProber). Anything else streams
    /// through a single AVAudioConverter into a temporary 16 kHz mono wav.
    public static func normalize(audioPath: String) throws -> NormalizedAudio {
        let url = URL(fileURLWithPath: audioPath)
        guard let source = try? AVAudioFile(forReading: url) else {
            return NormalizedAudio(path: audioPath, isTemporary: false)
        }
        let format = source.fileFormat
        if format.sampleRate == targetSampleRate, format.channelCount == targetChannelCount {
            return NormalizedAudio(path: audioPath, isTemporary: false)
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("bestasr-normalized-\(UUID().uuidString).wav")
        do {
            try convert(source, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return NormalizedAudio(path: destination.path, isTemporary: true)
    }

    /// Streams `source` through ONE AVAudioConverter instance into a 16 kHz
    /// mono wav. A single converter across all chunks keeps the resampler's
    /// filter state continuous — per-chunk converter rebuilds are exactly the
    /// upstream pattern this normalizer routes around.
    ///
    /// EOF strategy: reads up to the container's declared length, with a
    /// zero-length read as the second stop condition. Compressed containers
    /// may declare an *estimated* length; behavior for misdeclared lengths
    /// (VBR over/under-estimates) is tracked as a follow-up with a real
    /// fixture — the guard below refuses output that is drastically shorter
    /// than the declaration, so a bad estimate fails loud instead of
    /// producing a silently truncated file.
    private static func convert(_ source: AVAudioFile, to destination: URL) throws {
        let sourceFormat = source.processingFormat
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: false
        ) else {
            throw NormalizationError(message: "could not build the 16 kHz mono output format")
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
            throw NormalizationError(
                message: "no converter from \(Int(sourceFormat.sampleRate)) Hz "
                    + "\(sourceFormat.channelCount)ch to 16000 Hz 1ch"
            )
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let output = try AVAudioFile(
            forWriting: destination, settings: settings,
            commonFormat: .pcmFormatFloat32, interleaved: false
        )

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: chunkFrames)
        else {
            throw NormalizationError(message: "could not allocate the input buffer")
        }

        /// The input block cannot throw; read failures are captured here and
        /// surfaced after the pull loop — fail-loud, never a silent EOF.
        final class ReadState {
            var error: (any Error)?
            var exhausted = false
        }
        let state = ReadState()
        let provide: AVAudioConverterInputBlock = { _, outStatus in
            if state.exhausted || state.error != nil {
                outStatus.pointee = .endOfStream
                return nil
            }
            // Reading AT the end position throws (_GenericObjCError 0) instead
            // of returning an empty buffer — detect EOF from the position
            // ourselves. The zero-length guard below stays as the second line
            // of defense for compressed containers whose length is an estimate.
            let remaining = source.length - source.framePosition
            guard remaining > 0 else {
                state.exhausted = true
                outStatus.pointee = .endOfStream
                return nil
            }
            inputBuffer.frameLength = 0
            // Clamp in Int64 BEFORE the UInt32 conversion: AVAudioFrameCount(remaining)
            // traps (uncatchable) for remaining > UInt32.max (~27 h at 44.1 kHz) —
            // function arguments evaluate before min gets a chance to clamp.
            let framesToRead = AVAudioFrameCount(min(Int64(chunkFrames), remaining))
            do {
                try source.read(into: inputBuffer, frameCount: framesToRead)
            } catch {
                state.error = error
                outStatus.pointee = .endOfStream
                return nil
            }
            if inputBuffer.frameLength == 0 {
                state.exhausted = true
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return inputBuffer
        }

        conversion: while true {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat, frameCapacity: chunkFrames)
            else {
                throw NormalizationError(message: "could not allocate the output buffer")
            }
            var conversionError: NSError?
            let status = converter.convert(
                to: outputBuffer, error: &conversionError, withInputFrom: provide)
            if let readError = state.error {
                throw NormalizationError(
                    message: "reading the source failed mid-conversion: "
                        + readError.localizedDescription
                )
            }
            if let conversionError {
                throw NormalizationError(
                    message: "conversion failed: \(conversionError.localizedDescription)")
            }
            if outputBuffer.frameLength > 0 {
                try output.write(from: outputBuffer)
            }
            switch status {
            case .haveData:
                continue
            case .endOfStream:
                break conversion
            case .inputRanDry:
                // Only reachable when the input block returns .noDataNow, which
                // this block never does. If the converter reports it anyway the
                // state machine's invariant is broken — fail loud rather than
                // return a silently partial file (#36's whole failure family).
                throw NormalizationError(
                    message: "converter reported inputRanDry, which this pull "
                        + "loop never signals — refusing to emit a partial file")
            case .error:
                throw NormalizationError(message: "converter reported an error status")
            @unknown default:
                throw NormalizationError(
                    message: "converter returned unknown status \(status.rawValue)")
            }
        }

        // Degenerate-output guard: a conversion that "succeeds" while emitting
        // drastically less audio than the container declared is #36's failure
        // signature (87 minutes in, one 30-second cue out). The 50% floor is
        // deliberately loose — declared lengths on compressed containers are
        // estimates with a few percent error, never half.
        let sourceRate = source.fileFormat.sampleRate
        if sourceRate > 0, source.length > 0 {
            let expectedFrames = Double(source.length) / sourceRate * targetSampleRate
            if Double(output.length) < expectedFrames * 0.5 {
                throw NormalizationError(
                    message: "conversion produced \(output.length) frames where about "
                        + "\(Int(expectedFrames)) were declared — refusing the "
                        + "drastically truncated output"
                )
            }
        }
    }
}
