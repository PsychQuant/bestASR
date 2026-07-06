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
    ///
    /// Speaker-labeled references (#55, spec benchmark): a leading `Name: `
    /// whose exact name recurs on ≥2 cues is a speaker label — ASR output
    /// never contains it, so it must not count against the hypothesis. A
    /// one-off colon phrase is body text and stays. Cue texts themselves are
    /// untouched (design D2 — stripping happens at derivation only).
    public static func referenceText(from cues: [SRTCue]) -> String {
        let recurring = recurringSpeakerPrefixes(in: cues)
        guard !recurring.isEmpty else {
            return cues.map(\.text).joined(separator: " ")
        }
        return cues.map { cue in
            if let name = speakerPrefix(of: cue.text), recurring.contains(name) {
                return String(cue.text.dropFirst(name.count + 2))
            }
            return cue.text
        }.joined(separator: " ")
    }

    /// The candidate speaker name of a cue text — the part before a leading
    /// `<name>: ` where the name is ≤40 characters and contains no colon.
    private static func speakerPrefix(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let name = text[..<colon]
        let afterColon = text.index(after: colon)
        guard !name.isEmpty, name.count <= 40,
            afterColon < text.endIndex, text[afterColon] == " "
        else { return nil }
        return String(name)
    }

    private static func recurringSpeakerPrefixes(in cues: [SRTCue]) -> Set<String> {
        var counts: [String: Int] = [:]
        for cue in cues {
            if let name = speakerPrefix(of: cue.text) {
                counts[name, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value >= 2 }.keys)
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
