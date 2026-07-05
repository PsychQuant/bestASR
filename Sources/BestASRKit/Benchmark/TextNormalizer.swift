import Foundation

/// Text normalization applied to BOTH hypothesis and reference before error-
/// rate computation (design D4). Without it, CER/WER measures punctuation and
/// width noise instead of model quality.
///
/// Pipeline: Unicode NFKC (also folds fullwidth forms to halfwidth) →
/// lowercase → strip punctuation and symbols → collapse whitespace runs.
public enum TextNormalizer {
    public static func normalize(_ text: String) -> String {
        let nfkc = text.precomposedStringWithCompatibilityMapping.lowercased()
        var stripped = String.UnicodeScalarView()
        for scalar in nfkc.unicodeScalars {
            if CharacterSet.punctuationCharacters.contains(scalar) { continue }
            if CharacterSet.symbols.contains(scalar) { continue }
            stripped.append(scalar)
        }
        let collapsed = String(stripped)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return collapsed
    }

    /// Traditional→Simplified Han fold for zh metric comparison ONLY (#34 D7).
    /// Whisper-family models emit Simplified by default while this project's
    /// Chinese references are Traditional; folding BOTH sides (the well-defined
    /// many-to-one direction) makes CER measure recognition content instead of
    /// output script. Uses the system ICU transform — zero external deps.
    /// Never applied to ja/ko (Japanese kanji must not be rewritten) and never
    /// to the transcript files delivered to the user.
    public static func foldHanToSimplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }
}
