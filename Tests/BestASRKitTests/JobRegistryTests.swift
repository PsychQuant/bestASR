import Foundation
import Testing

@testable import BestASRMCPCore

/// spec mcp-surface (#86): the async job state machine, exercised with injected
/// work closures so no real engine is needed.
struct JobRegistryTests {
    @Test func `A completing job goes running then done and awaitResult returns the payload`() async {
        let reg = JobRegistry()
        let id = await reg.start {
            try? await Task.sleep(for: .milliseconds(80))
            return "the transcript"
        }
        // start records the job synchronously before the work runs.
        #expect(await reg.status(id) == .running)
        let outcome = await reg.awaitResult(id, cap: .seconds(2))
        #expect(outcome == .result("the transcript"))
        #expect(await reg.status(id) == .done)
    }

    @Test func `awaitResult caps the wait and returns stillRunning for a slow job`() async {
        let reg = JobRegistry()
        let id = await reg.start {
            try? await Task.sleep(for: .seconds(5))
            return "eventually"
        }
        let outcome = await reg.awaitResult(id, cap: .milliseconds(150))
        #expect(outcome == .stillRunning)
    }

    @Test func `A failing job surfaces the failed state and typed error`() async {
        let reg = JobRegistry()
        let id = await reg.start {
            throw JobError("boom: model missing")
        }
        let outcome = await reg.awaitResult(id, cap: .seconds(1))
        #expect(outcome == .failed("boom: model missing"))
        #expect(await reg.status(id) == .failed("boom: model missing"))
    }

    @Test func `A completed job stays fetchable within the retention window`() async {
        // Generous window so the first fetch reliably lands inside it even under
        // heavy parallel test load (the original single-test flake: a 0.1s window
        // could expire before the fetch ran).
        let reg = JobRegistry(retention: 30)
        let id = await reg.start { "done fast" }
        #expect(await reg.awaitResult(id, cap: .seconds(1)) == .result("done fast"))
        #expect(await reg.status(id) == .done)
    }

    @Test func `A completed job is evicted after the retention window elapses`() async {
        let reg = JobRegistry(retention: 0.2)
        let id = await reg.start { "done fast" }
        _ = await reg.awaitResult(id, cap: .seconds(1))   // ensure the work ran
        // Over-sleep well past the window: elapsed >> 0.2s regardless of load,
        // so this asserts the eviction direction without racing the scheduler.
        try? await Task.sleep(for: .milliseconds(700))
        #expect(await reg.status(id) == nil)              // evicted → unknown
        #expect(await reg.awaitResult(id, cap: .milliseconds(10)) == .unknown)
    }

    @Test func `An unknown job id reports unknown on both status and result`() async {
        let reg = JobRegistry()
        #expect(await reg.status("no-such-job") == nil)
        #expect(await reg.awaitResult("no-such-job", cap: .milliseconds(10)) == .unknown)
    }
}
