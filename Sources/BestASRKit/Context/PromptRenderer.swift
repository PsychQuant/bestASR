import Foundation

/// Renders loaded context into a natural-language vocabulary prompt — never
/// JSON (spec context-calibration: Render context into a natural-language
/// prompt with priority and budget; design D3).
///
/// Priority: names (each name, then its aliases) → terms → phrases. Items that
/// would exceed the budget are skipped whole and recorded as truncated.
public enum PromptRenderer {
    /// ~200-token budget, below Whisper's ~224 practical prompt limit; the
    /// WhisperKit engine additionally clamps encoded tokens as a safety net.
    public static let defaultTokenBudget = 200

    public struct Rendered: Sendable, Equatable {
        public let prompt: String?
        public let injected: [String]
        public let truncated: [String]
    }

    /// Conservative token estimate for budget purposes: CJK-range scalars
    /// count ~2 tokens each, other content ~1.5 tokens per whitespace word
    /// (design D3 heuristic; exactness is not required — truncation is always
    /// disclosed).
    static func estimatedTokens(_ item: String) -> Int {
        var cjk = 0
        var other = 0
        for scalar in item.unicodeScalars {
            switch scalar.value {
            case 0x2E80...0x9FFF, 0x3040...0x30FF, 0xAC00...0xD7AF,
                 0xF900...0xFAFF, 0x20000...0x2FA1F:
                cjk += 1
            default:
                other += 1
            }
        }
        let words = other > 0 ? max(1, item.split(whereSeparator: \.isWhitespace).count) : 0
        return cjk * 2 + Int((Double(words) * 1.5).rounded(.up))
    }

    public static func render(
        _ context: LoadedContext,
        tokenBudget: Int = defaultTokenBudget
    ) -> Rendered {
        // Priority classes (design D3): names + aliases, then terms, then phrases.
        var nameItems: [String] = []
        for name in context.names {
            nameItems.append(name.name)
            nameItems += name.aliases ?? []
        }
        let classes = [nameItems, context.allTerms, context.phrases]

        var injected: [String] = []
        var truncated: [String] = []
        var budget = tokenBudget
        var seen = Set<String>()
        // Once any class overflows, every lower-priority class is dropped
        // wholesale — the spec guarantees phrases fall before terms and terms
        // before names, which per-item skipping alone cannot promise.
        var exhausted = false

        for classItems in classes {
            var classTruncated = false
            for item in classItems {
                let value = item.trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty, !seen.contains(value) else { continue }
                seen.insert(value)
                let cost = estimatedTokens(value) + 1  // separator overhead
                if !exhausted, cost <= budget {
                    injected.append(value)
                    budget -= cost
                } else {
                    truncated.append(value)
                    classTruncated = true
                }
            }
            if classTruncated { exhausted = true }
        }

        return Rendered(
            prompt: injected.isEmpty ? nil : injected.joined(separator: ", "),
            injected: injected,
            truncated: truncated
        )
    }
}
