import Foundation

/// Edit-distance error rates (design D4):
/// CER = char-level Levenshtein(normalize(hyp), normalize(ref)) ÷ ref length;
/// WER = the same over whitespace-separated tokens.
public enum ErrorRate {
    /// Classic two-row Levenshtein — transcript-sized inputs, O(m·n) is fine.
    static func levenshtein<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Character error rate over normalized text. An empty reference with a
    /// non-empty hypothesis caps at 1.0 (fully wrong) instead of dividing by zero.
    public static func cer(hypothesis: String, reference: String) -> Double {
        let hyp = Array(TextNormalizer.normalize(hypothesis))
        let ref = Array(TextNormalizer.normalize(reference))
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(levenshtein(hyp, ref)) / Double(ref.count)
    }

    /// Word error rate over whitespace-tokenized normalized text.
    public static func wer(hypothesis: String, reference: String) -> Double {
        let hyp = TextNormalizer.normalize(hypothesis).split(separator: " ").map(String.init)
        let ref = TextNormalizer.normalize(reference).split(separator: " ").map(String.init)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(levenshtein(hyp, ref)) / Double(ref.count)
    }

    public static func compute(
        hypothesis: String, reference: String, kind: MetricKind
    ) -> Double {
        switch kind {
        case .cer: cer(hypothesis: hypothesis, reference: reference)
        case .wer: wer(hypothesis: hypothesis, reference: reference)
        }
    }
}
