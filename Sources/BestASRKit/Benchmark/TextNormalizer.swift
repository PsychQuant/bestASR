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
}
