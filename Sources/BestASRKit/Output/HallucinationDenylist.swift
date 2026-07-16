import Foundation

/// A curated list of known ASR "hallucination" phrases — boilerplate a decoder
/// emits over silent / music segments instead of real speech.
///
/// The default set is the **Whisper-family** artifact (YouTube-caption
/// contamination in the training data): "please like & subscribe" style outros
/// that surface verbatim over silence. For backends that never emit these
/// strings (e.g. Parakeet) matching is a harmless no-op — the denylist only
/// ever removes an exact known phrase, so a backend that doesn't produce it is
/// simply unaffected.
///
/// Structure is family-neutral (a flat phrase list, not Whisper-specific) so
/// other backends' repetition patterns can be appended, and leaves room for a
/// future `--denylist-file` override.
public struct HallucinationDenylist: Sendable {
    /// Phrases to strip. Matching is normalized (see `matches`) so spacing and
    /// punctuation jitter between decoder runs does not require a new entry.
    public let phrases: [String]

    public init(phrases: [String]) {
        self.phrases = phrases
    }

    /// Known Whisper-family Chinese boilerplate seen in the wild, plus a few
    /// common attribution / caption-farm outros. Kept short and
    /// high-specificity so it cannot plausibly collide with real speech.
    public static let `default` = HallucinationDenylist(phrases: [
        // The canonical "please like & subscribe" YouTube outro. 2026-07-15
        // evidence: three silent segments of a 28-minute meeting were all
        // filled with this exact string.
        "请不吝点赞订阅转发打赏支持明镜与点点栏目",
        "明镜与点点栏目",
        "點點欄目",
        // Generic caption-farm / attribution outros (both scripts).
        "感謝觀看",
        "感谢观看",
        "請訂閱",
        "请订阅",
        "字幕by",
        "字幕志愿者",
        "中文字幕志愿者",
    ])

    /// Normalize for comparison: drop whitespace and punctuation, then casefold.
    /// This absorbs the spacing / punctuation jitter Whisper adds between runs
    /// (`请不吝点赞 订阅…` vs `请不吝点赞订阅…`) without listing every variant.
    static func normalize(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(kept)).lowercased()
    }

    /// Minimum share of the cue (by normalized character length) that a denylist
    /// phrase must cover for the cue to count as a hallucination. Containment
    /// alone would let a short outro phrase nuke a long real sentence that merely
    /// mentions it; requiring the phrase to *dominate* the cue keeps genuine
    /// speech while still tolerating leading/trailing decoder filler around the
    /// boilerplate. Biased toward precision because this filter is on by default.
    static let coverageThreshold = 0.6

    /// A cue is a hallucination when its normalized text contains a normalized
    /// denylist phrase AND that phrase covers at least `coverageThreshold` of the
    /// cue. Not plain equality — Whisper often prepends filler ("嗯", punctuation)
    /// to the boilerplate — and not plain containment — that drops real sentences
    /// that happen to include a short outro phrase.
    public func matches(_ text: String) -> Bool {
        let needle = Self.normalize(text)
        guard !needle.isEmpty else { return false }
        let needleCount = needle.count
        return phrases.contains { phrase in
            let candidate = Self.normalize(phrase)
            guard !candidate.isEmpty, needle.contains(candidate) else { return false }
            return Double(candidate.count) >= Double(needleCount) * Self.coverageThreshold
        }
    }
}
