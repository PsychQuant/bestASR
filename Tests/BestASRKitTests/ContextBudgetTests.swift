import Foundation
import Testing

@testable import BestASRKit

/// Where the render budget comes from, and when rendering happens at all
/// (design D3, spec `Render context into a natural-language prompt with
/// priority and budget`).
struct ContextBudgetTests {

    /// A context directory holding enough terms that a 200-token budget
    /// truncates and a 224-token one truncates less — so "which budget was
    /// used" is observable rather than asserted against a number.
    private func makeContextDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctx-budget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let terms = (0..<120).map { "\"term-number-\($0)\"" }.joined(separator: ", ")
        let json = "{ \"version\": 1, \"terms\": [\(terms)] }"
        try json.write(
            to: dir.appendingPathComponent("context.json"), atomically: true, encoding: .utf8)
        return dir
    }

    /// Same injection shape the other CommandCore tests use: mock engines,
    /// fixed host, temp store, deterministic clock.
    private func core(engines: [any Engine]) -> CommandCore {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("core-\(UUID().uuidString)", isDirectory: true)
        return CommandCore(
            engines: engines,
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: scratch.appendingPathComponent("store")),
            probe: FakeClock(step: 1.0).probe())
    }

    /// The two budgets must actually differ on this fixture, or every other
    /// assertion here would be vacuous.
    @Test func `The fixture distinguishes a 200-token budget from a 224-token one`() throws {
        let dir = try makeContextDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let loaded = try #require(try ContextLoader.load(flag: dir.path))
        let at200 = PromptRenderer.render(loaded, tokenBudget: 200)
        let at224 = PromptRenderer.render(loaded, tokenBudget: 224)
        #expect(
            at200.injected.count < at224.injected.count,
            "fixture is too small to tell the budgets apart — the budget tests would be vacuous")
    }

    /// 4.1 — the budget comes from the selected engine, not the global constant.
    @Test func `Rendering uses the budget the engine declared`() throws {
        let dir = try makeContextDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subject = core(engines: [])

        let bundle = try #require(
            try subject.loadContext(flag: dir.path, capability: .supported(maxTokens: 224)))
        let rendered = try #require(bundle.rendered)

        let loaded = try #require(try ContextLoader.load(flag: dir.path))
        #expect(rendered.injected.count == PromptRenderer.render(loaded, tokenBudget: 224).injected.count)
        #expect(rendered.injected.count != PromptRenderer.render(loaded, tokenBudget: 200).injected.count)
    }

    /// 4.2 — D3: an engine that ignores conditioning text gets no render at all.
    /// Not "render and discard": the truncation figures would be real work
    /// producing a number that describes nothing.
    @Test func `An unsupported engine skips rendering entirely`() throws {
        let dir = try makeContextDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subject = core(engines: [])

        let bundle = try #require(try subject.loadContext(flag: dir.path, capability: .unsupported))
        #expect(bundle.rendered == nil, "an unsupported engine must not get a rendered prompt")
        #expect(bundle.loaded.directory == dir.path, "the directory is still disclosed")
    }

    /// 4.3 — a declared maximum of zero takes the same path as no support, so a
    /// backend can never be handed an empty-string prompt.
    @Test func `A zero declared budget takes the unsupported path`() throws {
        let dir = try makeContextDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subject = core(engines: [])

        let bundle = try #require(
            try subject.loadContext(flag: dir.path, capability: .supported(maxTokens: 0)))
        #expect(bundle.rendered == nil, "a zero budget must not produce a prompt")
    }

    // MARK: - 5.1 honest disclosure (spec `Explain discloses context usage`)

    /// The original complaint in one assertion: a backend that consumes no
    /// prompt must not be described as having had values injected. `injected
    /// (49)` reads as success, and the user acts on it by trimming their term
    /// list — which changes nothing, because nothing was ever injected.
    @Test func `Explain does not report an injected count for an unsupported backend`() throws {
        let dir = try makeContextDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subject = core(engines: [])
        let bundle = try #require(try subject.loadContext(flag: dir.path, capability: .unsupported))

        let explanation = CommandCore.contextExplanation(bundle).joined(separator: "\n")
        #expect(!explanation.contains("injected"), "got: \(explanation)")
        #expect(!explanation.contains("truncated"), "got: \(explanation)")
        #expect(explanation.contains("does not support context biasing"), "got: \(explanation)")
        #expect(explanation.contains(dir.path), "the directory is still disclosed")

        let reason = CommandCore.contextReasonLine(bundle)
        #expect(!reason.contains("value(s) injected"), "got: \(reason)")
        #expect(reason.contains("does not support context biasing"), "got: \(reason)")
    }

    /// The supported path must be untouched — this change is about removing a
    /// false claim, not about changing what a working run reports.
    @Test func `Explain still reports injected values for a supporting backend`() throws {
        let dir = try makeContextDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subject = core(engines: [])
        let bundle = try #require(
            try subject.loadContext(flag: dir.path, capability: .supported(maxTokens: 224)))

        let explanation = CommandCore.contextExplanation(bundle).joined(separator: "\n")
        #expect(explanation.contains("injected ("), "got: \(explanation)")
        #expect(!explanation.contains("does not support context biasing"))
        #expect(CommandCore.contextReasonLine(bundle).contains("value(s) injected"))
    }
}
