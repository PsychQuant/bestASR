import Foundation

/// The JSON-lines protocol between MLXAudioEngine and mlx_worker.py (#14;
/// spec mlx-audio-engine, design D1). One request per stdin line, one
/// response per stdout line; the worker prints a ready line after model load
/// so model-load cost lands in the warm-up pass, never the timed pass.
public enum MLXWorkerProtocol {
    public struct Request: Codable, Sendable, Equatable {
        public let id: Int
        public let audio: String
        public let language: String?

        public init(id: Int, audio: String, language: String?) {
            self.id = id
            self.audio = audio
            self.language = language
        }
    }

    public struct Segment: Codable, Sendable, Equatable {
        public let start: Double
        public let end: Double
        public let text: String
    }

    public struct Response: Codable, Sendable, Equatable {
        public let id: Int
        public let text: String?
        public let segments: [Segment]?
        public let language: String?
        public let error: String?
    }

    public struct Ready: Codable, Sendable, Equatable {
        public let ready: Bool
        public let model: String
    }

    public static func encode(_ request: Request) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(request), as: UTF8.self)
    }

    public static func decodeResponse(_ line: String) throws -> Response {
        try JSONDecoder().decode(Response.self, from: Data(line.utf8))
    }

    public static func decodeReady(_ line: String) -> Ready? {
        try? JSONDecoder().decode(Ready.self, from: Data(line.utf8))
    }

    /// Maps a worker response to the shared raw-transcription shape.
    /// Segments absent → whole text as one segment spanning 0..duration
    /// (spec: Output normalization).
    public static func rawTranscription(
        from response: Response, duration: Double?
    ) -> RawTranscription {
        let text = response.text ?? ""
        let segments: [RawTranscription.RawSegment]
        if let rows = response.segments, !rows.isEmpty {
            segments = rows.map { .init(start: $0.start, end: $0.end, text: $0.text) }
        } else if !text.isEmpty {
            segments = [.init(start: 0, end: duration ?? 0, text: text)]
        } else {
            segments = []
        }
        return RawTranscription(
            segments: segments, language: response.language, duration: duration)
    }
}
