import Foundation

/// Transcript writers for txt / json / srt / vtt (living spec transcript-output;
/// behavior identical to the archived Python implementation).
public enum TranscriptWriter {
    public static func render(_ transcript: Transcript, format: OutputFormat) -> String {
        switch format {
        case .txt: transcript.text
        case .json: renderJSON(transcript)
        case .srt: renderSRT(transcript)
        case .vtt: renderVTT(transcript)
        }
    }

    /// Resolve a format name, defaulting to txt; unknown names list the
    /// supported set (spec: Select writer by format with a default).
    public static func format(named name: String?) throws -> OutputFormat {
        guard let name, !name.isEmpty else { return .txt }
        guard let format = OutputFormat(rawValue: name.lowercased()) else {
            throw BestASRError.usage(
                "unsupported output format: '\(name)'; supported formats are "
                    + OutputFormat.allNames.joined(separator: ", ")
            )
        }
        return format
    }

    public static func write(
        _ transcript: Transcript, to path: String, format: OutputFormat
    ) throws {
        try render(transcript, format: format)
            .write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - json

    private static func renderJSON(_ transcript: Transcript) -> String {
        struct SegmentJSON: Codable {
            let id: Int
            let start: Double
            let end: Double
            let text: String
            let confidence: Double?
        }
        struct TranscriptJSON: Codable {
            let text: String
            let language: String?
            let duration: Double?
            let backend: String
            let model: String
            let segments: [SegmentJSON]
        }
        let document = TranscriptJSON(
            text: transcript.text,
            language: transcript.language,
            duration: transcript.duration,
            backend: transcript.backend,
            model: transcript.model,
            segments: transcript.segments.map {
                SegmentJSON(
                    id: $0.id, start: $0.start, end: $0.end, text: $0.text,
                    confidence: $0.confidence)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(document) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - srt / vtt

    /// `HH:MM:SS<sep>mmm` — SRT uses ",", VTT uses ".".
    static func timestamp(_ seconds: Double, millisSeparator: String) -> String {
        let totalMillis = Int((max(0, seconds) * 1000).rounded())
        let hours = totalMillis / 3_600_000
        let minutes = (totalMillis % 3_600_000) / 60_000
        let secs = (totalMillis % 60_000) / 1000
        let millis = totalMillis % 1000
        return String(
            format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, millisSeparator, millis)
    }

    private static func renderSRT(_ transcript: Transcript) -> String {
        transcript.segments.enumerated().map { index, seg in
            let start = timestamp(seg.start, millisSeparator: ",")
            let end = timestamp(seg.end, millisSeparator: ",")
            return "\(index + 1)\n\(start) --> \(end)\n\(seg.text)\n"
        }
        .joined(separator: "\n")
    }

    private static func renderVTT(_ transcript: Transcript) -> String {
        let cues = transcript.segments.map { seg in
            let start = timestamp(seg.start, millisSeparator: ".")
            let end = timestamp(seg.end, millisSeparator: ".")
            return "\(start) --> \(end)\n\(seg.text)\n"
        }
        .joined(separator: "\n")
        return "WEBVTT\n\n\(cues)"
    }
}
