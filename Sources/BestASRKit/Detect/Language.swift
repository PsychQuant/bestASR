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

    public static func metricKind(forLanguage language: String) -> MetricKind {
        let base = language.lowercased().split(separator: "-").first.map(String.init) ?? language
        return cerLanguages.contains(base) ? .cer : .wer
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
