import Foundation
import Testing
@testable import BestASRKit

struct OutputTests {
    let transcript = Transcript(
        text: "hello world",
        language: "en",
        duration: 2.5,
        backend: "whisperkit",
        model: "small",
        segments: [TranscriptSegment(id: 1, start: 0.0, end: 2.5, text: "hello world")]
    )

    @Test func `txt output is the transcript text`() {
        #expect(TranscriptWriter.render(transcript, format: .txt) == "hello world")
    }

    @Test func `json output is parseable and complete`() throws {
        let rendered = TranscriptWriter.render(transcript, format: .json)
        let object = try JSONSerialization.jsonObject(with: Data(rendered.utf8)) as? [String: Any]
        let json = try #require(object)
        for key in ["text", "language", "duration", "backend", "model", "segments"] {
            #expect(json[key] != nil, "missing key \(key)")
        }
        let segments = try #require(json["segments"] as? [[String: Any]])
        #expect(segments.count == 1)
        #expect(segments[0]["text"] as? String == "hello world")
    }

    @Test func `srt cue matches the living-spec example verbatim`() {
        // transcript-output SBE: comma milliseconds, 1-based index.
        let rendered = TranscriptWriter.render(transcript, format: .srt)
        #expect(rendered.contains("1\n00:00:00,000 --> 00:00:02,500\nhello world"))
    }

    @Test func `vtt starts with the header and uses dot milliseconds`() {
        let rendered = TranscriptWriter.render(transcript, format: .vtt)
        #expect(rendered.hasPrefix("WEBVTT"))
        #expect(rendered.contains("00:00:00.000 --> 00:00:02.500\nhello world"))
    }

    @Test func `Format resolution defaults to txt and rejects unknown names`() throws {
        #expect(try TranscriptWriter.format(named: nil) == .txt)
        #expect(try TranscriptWriter.format(named: "SRT") == .srt)
        do {
            _ = try TranscriptWriter.format(named: "docx")
            Issue.record("expected format resolution to throw")
        } catch let error as BestASRError {
            let message = error.errorDescription ?? ""
            for name in OutputFormat.allNames {
                #expect(message.contains(name))
            }
        }
    }

    @Test func `write persists the rendered content`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("out.txt").path
        try TranscriptWriter.write(transcript, to: path, format: .txt)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "hello world")
    }
}
