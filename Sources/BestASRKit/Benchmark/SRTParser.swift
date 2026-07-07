import Foundation

/// One parsed SubRip cue.
public struct SRTCue: Sendable, Equatable {
    public let index: Int
    public let start: Double
    public let end: Double
    public let text: String
    /// The cue's original non-empty lines — rolling-caption detection (#33)
    /// needs line boundaries that the space-joined `text` erases.
    public let lines: [String]

    public init(index: Int, start: Double, end: Double, text: String, lines: [String]? = nil) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
        self.lines = lines ?? [text]
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
        // Cues are anchored on TIMECODE LINES, not blank-line blocks (#33):
        // YouTube ASR sometimes puts a blank line between the timecode and
        // the text, and blank-line splitting silently DROPPED the orphaned
        // text block from the reference. Tolerate CRLF and BOM.
        let cleaned = content.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
        let lines = cleaned.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var marks: [Int] = []
        for (i, line) in lines.enumerated() where line.firstMatch(of: timecodeLine) != nil {
            marks.append(i)
        }

        for (k, markLine) in marks.enumerated() {
            guard let match = lines[markLine].firstMatch(of: timecodeLine) else { continue }
            // Text runs to the next cue, minus that cue's numeric index line.
            // A trailing number only counts as the NEXT cue's index when it
            // matches the expected sequence (#33 verify LOW: an index-less
            // compact SRT whose last text line is a number — lyric "42" —
            // must not be eaten).
            var textEnd = k + 1 < marks.count ? marks[k + 1] : lines.count
            if k + 1 < marks.count, textEnd - 1 > markLine,
                let trailing = Int(lines[textEnd - 1]),
                trailing == cues.count + 2 {
                textEnd -= 1
            }
            let textLines = lines[(markLine + 1)..<textEnd].filter { !$0.isEmpty }
            let index = markLine > 0 ? Int(lines[markLine - 1]) ?? cues.count + 1 : cues.count + 1
            cues.append(
                SRTCue(
                    index: index,
                    start: seconds(match.1, match.2, match.3, match.4),
                    end: seconds(match.5, match.6, match.7, match.8),
                    text: textLines.joined(separator: " "),
                    lines: Array(textLines)
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


    /// Collapses YouTube-ASR "rolling window" captions (#33): every cue
    /// repeats the previous cue's last line before appending new content,
    /// interleaved with ~10ms ghost cues that add nothing — raw cue count
    /// runs ~2x the real content, which would double the reference text and
    /// wreck WER. Detection is conservative: only when ≥30% of adjacent cue
    /// pairs show the rolling overlap (next cue's first line == this cue's
    /// last line) is the collapse applied; normal subtitles pass through
    /// IDENTICALLY. Collapse keeps, per cue, only the lines not already seen
    /// in the previous cue; cues left with nothing (ghosts) are dropped, and
    /// each survivor's end time extends to the next survivor's start.
    public static func collapseRollingCaptions(_ cues: [SRTCue]) -> [SRTCue] {
        guard cues.count >= 3 else { return cues }
        let pairs = zip(cues, cues.dropFirst())
        let overlapping = pairs.filter { prev, next in
            guard let tail = prev.lines.last, let head = next.lines.first else { return false }
            return !tail.isEmpty && tail == head
        }.count
        guard overlapping * 100 >= (cues.count - 1) * 30 else { return cues }
        // Second signal (#33 verify MEDIUM): line overlap alone false-triggers
        // on legitimate repetition (chorus lyrics, applause markers) and would
        // silently rewrite the ground truth. Real YouTube rolling captions
        // also interleave ~10ms ghost cues — require that signature too.
        let ghosts = cues.filter { $0.end - $0.start < 0.05 }.count
        guard ghosts * 100 >= cues.count * 10 else { return cues }
        FileHandle.standardError.write(Data(
            ("note: rolling-caption SRT detected (\(cues.count) raw cues, "
                + "\(ghosts) ghost cues) — collapsing to unique content\n").utf8))

        var survivors: [(cue: SRTCue, fresh: [String])] = []
        var previousLines: Set<String> = []
        for cue in cues {
            let fresh = cue.lines.filter { !previousLines.contains($0) }
            previousLines = Set(cue.lines)
            if !fresh.isEmpty {
                survivors.append((cue, fresh))
            }
        }
        return survivors.enumerated().map { i, entry in
            let end = i + 1 < survivors.count ? survivors[i + 1].cue.start : entry.cue.end
            return SRTCue(
                index: i + 1,
                start: entry.cue.start,
                end: max(end, entry.cue.start),
                text: entry.fresh.joined(separator: " "),
                lines: entry.fresh
            )
        }
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
        // Rolling-caption collapse is applied HERE so every reference
        // derivation gets it (#33) — detection is conservative, so normal
        // subtitles are untouched.
        let cues = collapseRollingCaptions(cues)
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
