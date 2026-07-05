import Foundation

/// Transcription-language resolution and metric-kind selection (design D4/D8).
public enum LanguageResolver {
    /// An explicit language is used verbatim (lowercased); `auto`/empty defers
    /// detection to the engine and is represented as nil.
    public static func resolve(_ requested: String?) -> String? {
        guard let requested else { return nil }
        let normalized = requested.trimmingCharacters(in: .whitespaces).lowercased()
        if normalized.isEmpty || normalized == "auto" { return nil }
        return normalized
    }

    /// Languages written without word spacing score with CER; whitespace-
    /// tokenized languages score with WER (spec benchmark: Compute accuracy
    /// metric selected by language). Region suffixes (zh-tw) match by prefix.
    static let cerLanguages: Set<String> = ["zh", "ja", "ko", "yue"]

    /// The base subtag of a BCP-47-ish language tag: "zh" from "zh-TW".
    /// Every language predicate in this project MUST go through this so the
    /// layers (metric selection, zh script fold) can never disagree on what
    /// counts as the same language family (#34 verify).
    static func baseSubtag(_ language: String) -> String {
        let lowered = language.lowercased()
        return lowered.split(separator: "-").first.map(String.init) ?? lowered
    }

    public static func metricKind(forLanguage language: String) -> MetricKind {
        cerLanguages.contains(baseSubtag(language)) ? .cer : .wer
    }

    /// True for any Chinese tag — zh, zh-TW, zh-Hant, zh-CN, … — and false
    /// for everything else. Drives the D7 script fold (#34). Deliberately
    /// narrow: `yue` (Cantonese) is outside D7's ruling and is not folded,
    /// and `auto`/nil never fold — an unresolved language cannot distinguish
    /// Chinese from Japanese text, and Japanese kanji must never be rewritten.
    /// Callers wanting folded zh scoring must pass an explicit zh tag.
    public static func isChinese(_ language: String?) -> Bool {
        guard let language else { return false }
        return baseSubtag(language) == "zh"
    }

    /// Fallback when the benchmark language is `auto`: infer from the ground-
    /// truth text itself — a majority of CJK/Kana/Hangul letters means CER.
    public static func metricKind(inferredFromReference text: String) -> MetricKind {
        var cjk = 0
        var letters = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            switch scalar.value {
            case 0x2E80...0x9FFF,    // CJK radicals, Han
                 0x3040...0x30FF,    // Hiragana, Katakana
                 0xAC00...0xD7AF,    // Hangul syllables
                 0xF900...0xFAFF,    // CJK compatibility ideographs
                 0x20000...0x2FA1F:  // CJK extensions
                cjk += 1
            default:
                break
            }
        }
        guard letters > 0 else { return .wer }
        return Double(cjk) / Double(letters) >= 0.5 ? .cer : .wer
    }
}
