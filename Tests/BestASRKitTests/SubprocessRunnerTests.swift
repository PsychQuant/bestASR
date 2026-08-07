import Foundation
import Testing

@testable import BestASRKit

/// Deadline contract for `SubprocessRunner` (#165 verify B1/B2/B3/B7).
///
/// Every test here is written to **fail rather than hang** when the contract is
/// broken. That is a deliberate reaction to verify finding B6: the original
/// regression test leaned on `.timeLimit`, which cannot preempt a thread parked
/// in a synchronous `waitUntilExit()` / `readDataToEndOfFile()`, so a regression
/// would have wedged CI instead of reporting a failure. Here the child always
/// exits on its own within a few seconds, and the assertion is on *elapsed
/// time*: a broken deadline shows up as "returned too late", never as a hang.
@Suite(.serialized) struct SubprocessRunnerDeadlineTests {

    /// Writes an executable `/bin/sh` stub and returns its path.
    private func stub(_ body: String) throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bestasr-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("stub.sh")
        try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (dir, script)
    }

    /// B1 — the deadline must cover the whole operation, not just the direct
    /// child's lifetime.
    ///
    /// The stub forks a background sleeper that inherits stdout, then exits 0
    /// immediately. The exit latch fires at once and `waitUntilExit()` returns,
    /// but the pipes stay open until the *grandchild* goes away. Before the fix
    /// the drain awaits were outside the deadline entirely, so the call returned
    /// only when the sleeper finished (~6 s) — precisely #91 recurring.
    @Test func `Deadline bounds the whole operation, not just the direct child`() async throws {
        let (dir, script) = try stub("sleep 6 &\nexit 0\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        let start = ContinuousClock.now
        var threw = false
        do {
            _ = try await SubprocessRunner.run(
                executable: script.path, arguments: [], timeout: 2, backend: "test")
        } catch {
            threw = true
        }
        let seconds = Double(start.duration(to: .now).components.seconds)

        #expect(threw, "a run bounded at 2s that cannot finish must throw, not succeed")
        #expect(
            seconds < 5,
            "deadline must bound the drain too — returned after \(seconds)s, which means it waited for the grandchild rather than the deadline")
    }

    /// B7 — a non-finite or non-positive timeout must be rejected at the entry
    /// point. `Date() > deadline` is always false for NaN, so the old watchdog
    /// looped forever; the public API must not accept a value that silently
    /// disables the only bound it promises.
    @Test func `A non-finite timeout is rejected instead of disabling the bound`() async throws {
        let (dir, script) = try stub("sleep 6\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        for bad in [Double.nan, .infinity, 0, -1] {
            let start = ContinuousClock.now
            var threw = false
            do {
                _ = try await SubprocessRunner.run(
                    executable: script.path, arguments: [], timeout: bad, backend: "test")
            } catch {
                threw = true
            }
            let seconds = Double(start.duration(to: .now).components.seconds)
            #expect(threw, "timeout \(bad) must be rejected")
            #expect(
                seconds < 3,
                "timeout \(bad) must be rejected up front — took \(seconds)s, so the process was actually spawned and waited on")
        }
    }

    /// B2 — cancelling the awaiting task must terminate the child and propagate
    /// `CancellationError`, not swallow it and spin. Before the fix `try?` ate
    /// the cancellation, every subsequent `Task.sleep` failed instantly, and the
    /// watchdog became a full-speed loop that still waited out the child.
    @Test func `Cancellation terminates the child and propagates`() async throws {
        let (dir, script) = try stub("sleep 6\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        let path = script.path
        let task = Task { () -> Bool in
            do {
                _ = try await SubprocessRunner.run(
                    executable: path, arguments: [], timeout: 30, backend: "test")
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        let start = ContinuousClock.now
        task.cancel()
        let sawCancellation = await task.value
        let seconds = Double(start.duration(to: .now).components.seconds)

        #expect(sawCancellation, "cancellation must surface as CancellationError")
        #expect(
            seconds < 4,
            "cancellation must not wait out the child — took \(seconds)s")
    }

    /// The ordinary path must keep working: a child that exits cleanly inside
    /// the budget returns its output with status 0.
    @Test func `A normal run returns stdout, stderr and status`() async throws {
        let (dir, script) = try stub("echo out; echo err 1>&2; exit 0\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        let (status, out, err) = try await SubprocessRunner.run(
            executable: script.path, arguments: [], timeout: 30, backend: "test")
        #expect(status == 0)
        #expect(out.contains("out"))
        #expect(err.contains("err"))
    }

    /// N1 (round-2 verify) — the timeout diagnostic must actually carry the
    /// output that was produced.
    ///
    /// The first rework read `box.collected` immediately after `teardown()`,
    /// with nothing joining the detached readers that `teardown()` had just
    /// unblocked. Reviewers reproduced the race at ~13% (2 of 15 runs came back
    /// with a bare message and no output at all), which contradicts the
    /// guarantee stated in `SubprocessRunner`'s own doc comment.
    ///
    /// Repeated because a race that fires one run in eight is invisible to a
    /// single-shot test — the thing being asserted is the *absence* of a
    /// scheduling window, so one green run proves very little.
    ///
    /// Honest limit: at the ~13% rate reviewers measured, five iterations still
    /// pass ~48% of the time WITH the bug present. This test is a regression
    /// net, not the proof — the proof is that the timeout path now waits for
    /// `bothDrained` before reading instead of racing the readers.
    @Test func `A timeout diagnostic carries the output the child already produced`()
        async throws
    {
        // Emits an identifiable payload well past the 64 KB pipe buffer, then
        // leaves a grandchild holding the pipe so the run must take the timeout
        // path with the readers still in flight.
        let (dir, script) = try stub(
            "awk 'BEGIN{for(i=0;i<8000;i++) print \"PAYLOAD-MARKER line to exceed the pipe buffer\"}'\n"
                + "( sleep 3 ) &\n"
                + "exit 0\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        for attempt in 1...5 {
            var message = ""
            do {
                _ = try await SubprocessRunner.run(
                    executable: script.path, arguments: [], timeout: 1, backend: "test")
                Issue.record("attempt \(attempt): expected a timeout")
            } catch let error as TranscriptionError {
                message = error.message
            }
            #expect(
                message.contains("PAYLOAD-MARKER"),
                "attempt \(attempt): timeout diagnostic dropped the child's output entirely — got: \(message)")
        }
    }

    /// M2 (round-2 verify) — B3's fix (SIGTERM → grace → SIGKILL → bounded reap)
    /// shipped with no coverage at all. A child that ignores SIGTERM must still
    /// be killed, and the call must still return on time.
    @Test func `A child ignoring SIGTERM is escalated to SIGKILL within the budget`()
        async throws
    {
        let (dir, script) = try stub("trap '' TERM\nsleep 10\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        let start = ContinuousClock.now
        var message = ""
        do {
            _ = try await SubprocessRunner.run(
                executable: script.path, arguments: [], timeout: 1, backend: "test")
            Issue.record("expected a timeout")
        } catch let error as TranscriptionError {
            message = error.message
        }
        let seconds = Double(start.duration(to: .now).components.seconds)

        #expect(message.contains("timed out"), "got: \(message)")
        #expect(
            seconds < 6,
            "a SIGTERM-ignoring child must be SIGKILLed and the call still return on time — took \(seconds)s")
    }

    /// A child that outruns its budget must fail as a *timeout*, within the
    /// budget — this is the branch the previous PR shipped with no coverage at
    /// all (verify I3).
    @Test func `A child that outruns its budget is killed and reported as a timeout`()
        async throws
    {
        let (dir, script) = try stub("sleep 6\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        let start = ContinuousClock.now
        var message = ""
        do {
            _ = try await SubprocessRunner.run(
                executable: script.path, arguments: [], timeout: 1, backend: "test")
            Issue.record("expected a timeout error")
        } catch let error as TranscriptionError {
            message = error.message
        }
        let seconds = Double(start.duration(to: .now).components.seconds)

        #expect(message.contains("timed out"), "got: \(message)")
        #expect(seconds < 5, "timeout fired late (\(seconds)s)")
    }
}
