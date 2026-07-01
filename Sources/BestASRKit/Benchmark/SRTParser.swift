import Foundation

/// One parsed SubRip cue.
public struct SRTCue: Sendable, Equatable {
    public let index: Int
    public let start: Double
    public let end: Double
    public let text: String

    public init(index: Int, start: Double, end: Double, text: String) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Parses `.srt` ground-truth references (spec benchmark: Parse SRT reference
/// into ground truth). Input parsing lives in the benchmark capability by
/// design (D5) — the transcript-output writers stay output-only.
public enum SRTParser {
    /// `HH:MM:SS,mmm --> HH:MM:SS,mmm` (comma canonical; dot tolerated).
    private static let timecodeLine = #/(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})/#

    public static func parse(fileAt path: String) throws -> [SRTCue] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw BestASRError.usage("reference file not found: \(path)")
        }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw BestASRError.usage("cannot read reference file as UTF-8 text: \(path)")
        }
        let cues = try parse(content, sourceName: path)
        return cues
    }

    public static func parse(_ content: String, sourceName: String = "<inline>") throws -> [SRTCue] {
        var cues: [SRTCue] = []
        // Blocks are separated by blank lines; tolerate CRLF and BOM.
        let cleaned = content.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = cleaned.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard !lines.isEmpty else { continue }

            // Locate the timecode line (usually line 2, after the index).
            guard let timecodeAt = lines.firstIndex(where: { $0.firstMatch(of: timecodeLine) != nil }),
                  let match = lines[timecodeAt].firstMatch(of: timecodeLine)
            else { continue }

            let index = timecodeAt > 0 ? Int(lines[timecodeAt - 1]) ?? cues.count + 1 : cues.count + 1
            let text = lines[(timecodeAt + 1)...].joined(separator: " ")
            cues.append(
                SRTCue(
                    index: index,
                    start: seconds(match.1, match.2, match.3, match.4),
                    end: seconds(match.5, match.6, match.7, match.8),
                    text: text
                )
            )
        }

        guard !cues.isEmpty else {
            throw BestASRError.usage(
                "no valid SRT cues found in \(sourceName): expected blocks with an "
                    + "HH:MM:SS,mmm --> HH:MM:SS,mmm timecode line"
            )
        }
        return cues
    }

    /// Ground-truth reference text: ordered cue texts joined by a space (word
    /// boundaries survive for WER; normalization collapses whitespace anyway).
    public static func referenceText(from cues: [SRTCue]) -> String {
        cues.map(\.text).joined(separator: " ")
    }

    private static func seconds(
        _ h: Substring, _ m: Substring, _ s: Substring, _ ms: Substring
    ) -> Double {
        let hours = Double(h) ?? 0
        let minutes = Double(m) ?? 0
        let secs = Double(s) ?? 0
        // "5" means 500ms in a 3-digit field; pad to interpret correctly.
        let padded = ms.padding(toLength: 3, withPad: "0", startingAt: 0)
        let millis = Double(padded) ?? 0
        return hours * 3600 + minutes * 60 + secs + millis / 1000
    }
}
