import AVFoundation
import Foundation

/// Probes audio files with the platform audio framework — no ffmpeg (spec
/// system-detection: Probe audio file properties; design D8).
public enum AudioProber {
    public static func probe(path: String, requestedLanguage: String? = nil) throws -> AudioInfo {
        guard FileManager.default.fileExists(atPath: path) else {
            throw BestASRError.usage("audio file not found: \(path)")
        }
        let url = URL(fileURLWithPath: path)
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw BestASRError.usage(
                "cannot read '\(path)' as audio: \(error.localizedDescription)"
            )
        }

        let format = file.fileFormat
        let sampleRate = format.sampleRate
        let duration = sampleRate > 0 ? Double(file.length) / sampleRate : nil
        return AudioInfo(
            path: path,
            duration: duration,
            format: url.pathExtension.lowercased().isEmpty ? nil : url.pathExtension.lowercased(),
            sampleRate: sampleRate > 0 ? Int(sampleRate) : nil,
            channels: Int(format.channelCount),
            language: LanguageResolver.resolve(requestedLanguage)
        )
    }
}
