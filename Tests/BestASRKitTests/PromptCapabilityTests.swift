import Foundation
import Testing

@testable import BestASRKit

/// The capability declaration itself (design D1/D2, spec `Common engine
/// interface`).
///
/// The type carries the zero-budget rule rather than leaving it to callers:
/// "declared supported with a maximum of zero" and "declared unsupported" must
/// be indistinguishable downstream, and an invariant every call site has to
/// remember is an invariant that eventually gets forgotten.
struct PromptCapabilityTests {

    @Test func `An unsupported engine has no usable budget`() {
        #expect(PromptCapability.unsupported.effectiveBudget == nil)
        #expect(PromptCapability.unsupported.supportsPrompt == false)
    }

    @Test func `A supported engine reports the budget it declared`() {
        #expect(PromptCapability.supported(maxTokens: 224).effectiveBudget == 224)
        #expect(PromptCapability.supported(maxTokens: 224).supportsPrompt)
    }

    /// Spec `Common engine interface`: "A backend that declares support with a
    /// maximum token count of zero SHALL be treated identically to a backend
    /// that declares no support." Negative is folded in for the same reason —
    /// there is no sensible reading of it, and silently rendering into a
    /// negative budget is worse than declining.
    @Test func `A zero or negative declared maximum is treated as no support`() {
        for bogus in [0, -1, Int.min] {
            let capability = PromptCapability.supported(maxTokens: bogus)
            #expect(
                capability.effectiveBudget == nil,
                "maxTokens \(bogus) must not yield a usable budget")
            #expect(capability.supportsPrompt == false, "maxTokens \(bogus) must not claim support")
        }
    }

    /// D1 rejected a third "supported, limit unknown" case because nothing in
    /// the tree needs it. This pins that decision: the type is exhaustively
    /// handled by two branches, so adding a third later is a deliberate,
    /// visible act rather than a silent widening.
    @Test func `The capability has exactly two shapes`() {
        let cases: [PromptCapability] = [.unsupported, .supported(maxTokens: 1)]
        for capability in cases {
            switch capability {
            case .unsupported, .supported:
                continue  // exhaustive without a default — if a case is added, this stops compiling
            }
        }
        #expect(cases.count == 2)
    }
}
