import Foundation

/// The one correct way to spawn a child process in BestASRKit.
///
/// The contract is deliberately narrow and stated in terms of what is actually
/// guaranteed, because the previous version of this file promised more than it
/// delivered (see "What this does NOT guarantee" below):
///
/// 1. **Both pipes are drained concurrently, starting before any wait.** A child
///    that writes past the OS pipe buffer (64 KB on Darwin) blocks in `write(2)`
///    forever if nobody reads, and the parent then blocks forever waiting for it.
///    Neither process burns CPU, so it looks like "slow", not "hung". That bug
///    shipped twice — #91 (external adapter, 1-hour CI hang) and #165
///    (`WhisperCppEngine`, any audio past ~63 minutes).
///
/// 2. **One deadline covers the whole operation**, not just the child's
///    lifetime. The operation is complete only when the process has exited *and*
///    both drains have finished; the deadline races that whole condition. The
///    first attempt at this fix bounded only the child's lifetime, so a
///    grandchild inheriting the pipes could still wedge the parent forever after
///    the direct child exited cleanly (#165 verify B1 — #91 recurring inside its
///    own fix).
///
/// 3. **The budget is validated and monotonic.** A non-finite or non-positive
///    timeout is rejected at the entry point rather than silently disabling the
///    bound, and elapsed time is measured with `ContinuousClock`, so adjusting
///    the system clock cannot extend a deadline (#165 verify B7).
///
/// 4. **Cancellation is honoured, not swallowed.** Cancelling the awaiting task
///    terminates the child and propagates `CancellationError` (#165 verify B2).
///
/// 5. **Output collected before a failure is preserved.** Timeouts and non-zero
///    exits still return what was read, so the diagnostic is not thrown away.
///
/// ## What this does NOT guarantee
///
/// **Descendants are not killed.** `Foundation.Process` does not expose
/// `posix_spawnattr`, so we cannot put the child in its own process group; on
/// timeout we signal the direct child only. A grandchild that ignores the closed
/// pipes keeps running. What guarantee 2 buys is that such a grandchild can no
/// longer wedge *us* — the call still returns on time. Killing the whole group
/// needs a lower-level spawn and is tracked in #170. Do not restate this as
/// "descendants are handled".
public enum SubprocessRunner {

    /// Thread-safe collector for the two drains. Readers are detached and
    /// blocking; this box is what lets the deadline path read whatever arrived
    /// without awaiting a read that may never return (see guarantee 2).
    final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()
        private var outDone = false
        private var errDone = false

        func finishOut(_ data: Data) { lock.withLock { out = data; outDone = true } }
        func finishErr(_ data: Data) { lock.withLock { err = data; errDone = true } }
        var bothDrained: Bool { lock.withLock { outDone && errDone } }
        var collected: (String, String) {
            lock.withLock {
                (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
            }
        }
    }

    /// Thread-safe "the child really exited" latch, flipped by the
    /// terminationHandler (which fires on a private queue). We loop on this
    /// rather than `Process.isRunning`, whose spurious `false` right after
    /// `run()` under load skipped the watchdog entirely — the 1-hour CI hang
    /// of #91.
    final class ExitLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var exited = false
        var isSet: Bool { lock.withLock { exited } }
        func set() { lock.withLock { exited = true } }
    }

    /// How often the completion condition is polled.
    private static let pollInterval = Duration.milliseconds(20)
    /// Grace between SIGTERM and SIGKILL, and the bounded reap after SIGKILL.
    private static let graceInterval = Duration.milliseconds(500)

    /// Spawn `executable`, drain both pipes concurrently, and return once the
    /// process has exited and both drains have finished — or fail, on time, if
    /// that does not happen within `timeout`.
    ///
    /// - Throws: `TranscriptionError` for an invalid budget, a launch failure,
    ///   or a timeout; `CancellationError` if the awaiting task is cancelled.
    /// - Returns: `(exit status, stdout, stderr)`.
    /// - Parameters:
    ///   - environment: replaces the child's environment when non-nil.
    ///   - currentDirectory: working directory for the child when non-nil.
    public static func run(
        executable: String, arguments: [String], timeout: TimeInterval, backend: String,
        environment: [String: String]? = nil, currentDirectory: URL? = nil
    ) async throws -> (Int32, String, String) {
        // Guarantee 3 — reject a budget that would silently remove the bound.
        // NaN in particular made every `now > deadline` comparison false, which
        // is how a "hard deadline" turned into an unbounded loop (#165 B7).
        guard timeout.isFinite, timeout > 0 else {
            throw TranscriptionError(
                backend: backend,
                message: "invalid subprocess timeout \(timeout) — must be finite and positive",
                underlying: nil)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let exited = ExitLatch()
        // Installed BEFORE run() so an instant exit can never miss the latch.
        process.terminationHandler = { _ in exited.set() }

        do {
            try process.run()
        } catch {
            throw TranscriptionError(
                backend: backend,
                message: "cannot launch '\(executable)': \(error.localizedDescription)",
                underlying: error)
        }

        // Guarantee 1 — drains start before any wait. They are detached and
        // blocking; the box (not an `await`) is how the deadline path reads
        // them, so a drain that never returns cannot extend the deadline.
        let box = OutputBox()
        Task.detached { box.finishOut(outPipe.fileHandleForReading.readDataToEndOfFile()) }
        Task.detached { box.finishErr(errPipe.fileHandleForReading.readDataToEndOfFile()) }

        // Idempotent teardown, shared by the timeout and cancellation paths.
        let teardown: @Sendable () -> Void = {
            if !exited.isSet { process.terminate() }
            // Closing our read ends unblocks the detached drains even when a
            // grandchild still holds the write end (#51 verify M4).
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()
        }

        do {
            let timedOut = try await withTaskCancellationHandler {
                try await raceCompletion(exited: exited, box: box, timeout: timeout)
            } onCancel: {
                teardown()
            }

            if timedOut {
                await terminate(process, exited: exited)
                teardown()
                // `teardown()` *unblocks* the detached readers by closing our
                // read ends — but unblocking is not finishing. They still have
                // to be scheduled and write into the box. Reading it on the very
                // next line left a window in which the diagnostic came back with
                // no output at all; reviewers reproduced that in ~13% of runs
                // (#165 round-2 N1), which contradicted guarantee 5 above.
                //
                // Bounded, because a diagnostic is not worth extending the
                // deadline for: if the readers cannot settle in the grace
                // window we report with whatever arrived.
                await settleDrains(box)
                let (out, err) = box.collected
                throw TranscriptionError(
                    backend: backend,
                    message: timeoutMessage(
                        executable: executable, timeout: timeout, stdout: out, stderr: err),
                    underlying: nil)
            }
        } catch is CancellationError {
            // Guarantee 4 — the child dies with us and the cancellation is
            // visible to the caller instead of being swallowed by `try?`.
            await terminate(process, exited: exited)
            teardown()
            throw CancellationError()
        }

        let (stdout, stderr) = box.collected
        return (process.terminationStatus, stdout, stderr)
    }

    /// Races the real completion condition — process exited **and** both drains
    /// finished — against the deadline. Returns `true` if the deadline won.
    ///
    /// `Task.sleep` is the only suspension point and its `CancellationError` is
    /// deliberately propagated: swallowing it with `try?` is what turned the old
    /// watchdog into a busy-spin that still waited out the child (#165 B2).
    private static func raceCompletion(
        exited: ExitLatch, box: OutputBox, timeout: TimeInterval
    ) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while true {
            if exited.isSet && box.bothDrained { return false }
            if ContinuousClock.now >= deadline { return true }
            try await Task.sleep(for: pollInterval)
        }
    }

    /// Waits, briefly and boundedly, for the detached drains to finish writing
    /// into the box after `teardown()` has unblocked them (#165 round-2 N1).
    ///
    /// Cancellation is checked explicitly rather than swallowed by `try?` — the
    /// same discipline as the watchdog, since this runs on the failure path
    /// where it would be easy to stop caring.
    private static func settleDrains(_ box: OutputBox) async {
        let deadline = ContinuousClock.now.advanced(by: graceInterval)
        while !box.bothDrained && ContinuousClock.now < deadline {
            if Task.isCancelled { return }
            try? await Task.sleep(for: pollInterval)
        }
    }

    /// SIGTERM, grace, SIGKILL, then a *bounded* reap. The old code called an
    /// unbounded synchronous `waitUntilExit()` after SIGKILL, so a child parked
    /// in uninterruptible I/O could still hang the caller past its deadline
    /// (#165 B3). `kill`'s return value is inspected rather than discarded.
    private static func terminate(_ process: Process, exited: ExitLatch) async {
        guard !exited.isSet else { return }
        process.terminate()
        try? await Task.sleep(for: graceInterval)
        if !exited.isSet {
            let pid = process.processIdentifier
            // A pid of 0/-1 means we have nothing safe to signal; ESRCH means it
            // is already gone. Never signal a pid we cannot vouch for — that is
            // the pid-reuse hazard tracked in #170.
            if pid > 0 && kill(pid, SIGKILL) != 0 && errno != ESRCH {
                FileHandle.standardError.write(
                    Data("warning: SIGKILL for pid \(pid) failed (errno \(errno))\n".utf8))
            }
        }
        // Bounded reap — never an open-ended wait.
        let reapDeadline = ContinuousClock.now.advanced(by: graceInterval)
        while !exited.isSet && ContinuousClock.now < reapDeadline {
            try? await Task.sleep(for: pollInterval)
        }
    }

    /// Guarantee 5 — a timeout keeps whatever was collected, because "it timed
    /// out" alone is rarely enough to tell why.
    private static func timeoutMessage(
        executable: String, timeout: TimeInterval, stdout: String, stderr: String
    ) -> String {
        var message = "'\(executable)' timed out after \(Int(timeout))s and was terminated"
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty { message += "; stderr: \(err.suffix(300))" }
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if err.isEmpty && !out.isEmpty { message += "; stdout: \(out.suffix(300))" }
        return message
    }
}
