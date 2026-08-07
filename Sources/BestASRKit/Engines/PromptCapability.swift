import Foundation

/// Whether a backend consumes a decoder conditioning prompt, and how much of
/// one it can take.
///
/// "Prompt" here means the ASR decoder's conditioning text — Whisper's
/// `initial_prompt` / `promptTokens` — not a prompt in the LLM sense. The
/// distinction matters because the two live at different layers and only one of
/// them exists in this codebase.
///
/// ## Why this type exists
///
/// The token budget used to be a single global constant applied to every
/// backend. Only two of the engines in this package actually read the prompt;
/// for the rest the whole render-and-truncate pipeline ran and the result was
/// discarded — while the CLI still reported `injected (N)`. The system claimed
/// to have done something it had not. Measured on a real run: 102 context items
/// produced "injected (49) / truncated (53)" against a backend that consumed
/// none of them, and the two terms the user cared about were both in the
/// "injected" list and both mis-transcribed.
///
/// ## Two cases, deliberately
///
/// An earlier proposal had a third case — supported, but with an unknown limit,
/// leaving truncation to the backend. It is not here because nothing in the tree
/// needs it: both Whisper-family backends cap at the same measured 224. Adding a
/// case with no instance would oblige every conformer, and every future engine
/// author, to handle a branch whose semantics could not be validated against
/// anything real. If a backend that genuinely cannot state a limit shows up,
/// the case can be added then — with a concrete instance to define it against.
public enum PromptCapability: Sendable, Equatable {
    /// The backend ignores conditioning text. Nothing should be rendered for it.
    case unsupported

    /// The backend accepts conditioning text up to `maxTokens` tokens.
    ///
    /// Tokens, not characters and not items — the renderer measures in tokens
    /// because that is what the decoder window is denominated in.
    case supported(maxTokens: Int)

    /// The budget actually usable, or `nil` when there is none.
    ///
    /// A declared maximum of zero — or, defensively, a negative one — collapses
    /// to `nil` rather than being passed downstream. The spec requires zero to
    /// behave exactly like `unsupported`, and putting that rule in the type
    /// means no call site can forget it or implement it slightly differently.
    /// Rendering into a zero budget would otherwise produce an empty prompt and
    /// hand the backend a meaningless empty string.
    public var effectiveBudget: Int? {
        switch self {
        case .unsupported:
            return nil
        case .supported(let maxTokens):
            return maxTokens > 0 ? maxTokens : nil
        }
    }

    /// Whether context biasing can do anything at all for this backend.
    public var supportsPrompt: Bool { effectiveBudget != nil }
}
