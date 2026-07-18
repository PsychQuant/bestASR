import AVFoundation
import Foundation

/// Slices audio into fixed-length windows for fixed-window backends (#106:
/// SenseVoice accepts 0.2–30 s of samples per call and hard-fails beyond).
/// Pure frame slicing — no resampling: the Engine-protocol seam has already
/// normalized input to 16 kHz mono WAV before any engine sees it (#36), so a
/// 30 s window is exactly the backend's 480 000-sample ceiling.
enum AudioWindower {
    struct Window: Sendable {
        let path: String
        let start: Double
        let end: Double
        /// True when `path` is a temporary slice the caller must remove.
        let isTemporary: Bool
    }

    /// Returns a single passthrough window when the file already fits.
    /// Otherwise writes `bestasr-window-*.wav` slices to tmp; the caller
    /// owns cleanup of every `isTemporary` window. A final remainder shorter
    /// than `minSeconds` (0.2 s for SenseVoice) is dropped — it is below the
    /// backend's floor and carries no intelligible speech.
    static func slice(
        audioPath: String, maxSeconds: Double, minSeconds: Double
    ) throws -> [Window] {
        let source = try AVAudioFile(forReading: URL(fileURLWithPath: audioPath))
        let rate = source.processingFormat.sampleRate
        guard rate > 0 else {
            throw BestASRError.runtime("cannot window '\(audioPath)': zero sample rate")
        }
        let total = source.length
        let maxFrames = AVAudioFramePosition(maxSeconds * rate)
        let minFrames = AVAudioFramePosition(minSeconds * rate)
        let duration = Double(total) / rate
        if total <= maxFrames {
            return [Window(path: audioPath, start: 0, end: duration, isTemporary: false)]
        }

        var windows: [Window] = []
        var position: AVAudioFramePosition = 0
        do {
            while position < total {
                let remaining = total - position
                if remaining < minFrames { break }  // sub-floor tail: dropped
                let frames = min(AVAudioFramePosition(maxFrames), remaining)
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bestasr-window-\(UUID().uuidString).wav")
                try writeSlice(
                    of: source, from: position, frames: AVAudioFrameCount(frames),
                    to: destination)
                windows.append(
                    Window(
                        path: destination.path,
                        start: Double(position) / rate,
                        end: Double(position + frames) / rate,
                        isTemporary: true))
                position += frames
            }
        } catch {
            cleanup(windows)  // never leak half-written slices on failure
            throw error
        }
        return windows
    }

    static func cleanup(_ windows: [Window]) {
        for window in windows where window.isTemporary {
            try? FileManager.default.removeItem(atPath: window.path)
        }
    }

    private static func writeSlice(
        of source: AVAudioFile, from position: AVAudioFramePosition,
        frames: AVAudioFrameCount, to destination: URL
    ) throws {
        let format = source.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let output = try AVAudioFile(
            forWriting: destination, settings: settings,
            commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw BestASRError.runtime("could not allocate a \(frames)-frame window buffer")
        }
        source.framePosition = position
        try source.read(into: buffer, frameCount: frames)
        try output.write(from: buffer)
    }
}
