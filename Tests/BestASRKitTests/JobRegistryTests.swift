import Foundation
import Testing

@testable import BestASRMCPCore

/// spec mcp-surface (#86): the async job state machine, exercised with injected
/// work closures so no real engine is needed. Time-dependent behavior runs on an
/// injected clock and completion gates — never real sleeps racing the scheduler
/// (the CI runner starves tasks hard enough that an 80 ms work closure once
/// missed a 2-second wait cap).
struct JobRegistryTests {
    /// Parks a work closure until the test explicitly releases it, so ordering
    /// assertions (`.running` before completion) cannot race the scheduler.
    private actor Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func open() {
            opened = true
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// Test-controlled retention clock: time advances only when told to.
    private final class FakeNow: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSinceReferenceDate: 0)
        var now: Date { lock.withLock { date } }
        func advance(by seconds: TimeInterval) { lock.withLock { date += seconds } }
    }

    @Test func `A completing job goes running then done and awaitResult returns the payload`() async {
        let reg = JobRegistry()
        let gate = Gate()
        let id = await reg.start {
            await gate.wait()
            return "the transcript"
        }
        // start records the job synchronously; the gate keeps the work parked,
        // so this observes .running deterministically.
        #expect(await reg.status(id) == .running)
        await gate.open()
        // Wide cap: awaitResult returns as soon as the job is terminal, so the
        // cap only bounds scheduler delay, not test duration.
        let outcome = await reg.awaitResult(id, cap: .seconds(30))
        #expect(outcome == .result("the transcript"))
        #expect(await reg.status(id) == .done)
    }

    @Test func `awaitResult caps the wait and returns stillRunning for a slow job`() async {
        let reg = JobRegistry()
        let gate = Gate()
        let id = await reg.start {
            await gate.wait()   // opened only after the cap — the job outlives it by construction
            return "eventually"
        }
        let outcome = await reg.awaitResult(id, cap: .milliseconds(150))
        #expect(outcome == .stillRunning)
        await gate.open()   // unpark so the work task does not leak past the test
    }

    @Test func `A failing job surfaces the failed state and typed error`() async {
        let reg = JobRegistry()
        let id = await reg.start {
            throw JobError("boom: model missing")
        }
        let outcome = await reg.awaitResult(id, cap: .seconds(30))
        #expect(outcome == .failed("boom: model missing"))
        #expect(await reg.status(id) == .failed("boom: model missing"))
    }

    @Test func `A completed job stays fetchable within the retention window`() async {
        let clock = FakeNow()
        let reg = JobRegistry(retention: 0.2, now: { clock.now })
        let id = await reg.start { "done fast" }
        #expect(await reg.awaitResult(id, cap: .seconds(30)) == .result("done fast"))
        // The clock never advances → still inside the window no matter how slow the runner.
        #expect(await reg.status(id) == .done)
    }

    @Test func `A completed job is evicted after the retention window elapses`() async {
        let clock = FakeNow()
        let reg = JobRegistry(retention: 0.2, now: { clock.now })
        let id = await reg.start { "done fast" }
        #expect(await reg.awaitResult(id, cap: .seconds(30)) == .result("done fast"))
        clock.advance(by: 10)                             // expiry passes purely in fake time
        #expect(await reg.status(id) == nil)              // evicted → unknown
        #expect(await reg.awaitResult(id, cap: .milliseconds(10)) == .unknown)
    }

    @Test func `An unknown job id reports unknown on both status and result`() async {
        let reg = JobRegistry()
        #expect(await reg.status("no-such-job") == nil)
        #expect(await reg.awaitResult("no-such-job", cap: .milliseconds(10)) == .unknown)
    }

    /// verify HIGH-1: the registry must be actually bounded, not just lazily
    /// evicted on access. A completed job that is never re-accessed must still be
    /// dropped — otherwise the common path (poll to done, stop) leaks the full
    /// transcript until process exit. Uses `count` so the assertion does not
    /// itself access the job (which would trigger lazy eviction and mask the leak).
    @Test func `A completed job is swept on the next start, not only lazily on access`() async {
        let clock = FakeNow()
        let reg = JobRegistry(retention: 0.2, now: { clock.now })
        let id = await reg.start { "leaked payload" }
        // Ensure the work completed (records completedAt at fake-now t0). This
        // access happens before the clock moves, so it cannot lazily evict.
        #expect(await reg.awaitResult(id, cap: .seconds(30)) == .result("leaked payload"))
        clock.advance(by: 10)            // well past the retention window
        #expect(await reg.count == 1)    // still resident — never re-accessed, no background reaper
        _ = await reg.start { "fresh" }  // a new job sweeps expired entries
        #expect(await reg.count == 1)    // only the fresh job remains — the stale one was swept, not leaked
    }
}
