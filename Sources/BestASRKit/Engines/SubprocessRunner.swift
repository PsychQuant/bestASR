import Foundation

/// The one correct way to spawn a child process in BestASRKit.
///
/// Two invariants, each learned from a shipped hang:
///
/// 1. **Both pipes are drained concurrently, before waiting on exit.** A child
///    that writes past the OS pipe buffer (64 KB on Darwin) blocks in `write(2)`
///    forever if nobody reads; the parent then blocks forever in
///    `waitUntilExit()`. Neither process burns CPU, so it looks like "slow",
///    not "hung". This shipped twice — #91 (external adapter, 1-hour CI hang)
///    and #165 (`WhisperCppEngine`, any audio past ~63 minutes) — because the
///    fix for the first lived only in the engine that hit it.
///
/// 2. **Every spawn has a deadline.** SIGTERM on expiry, SIGKILL if the child
///    lingers, then our pipe read ends are closed so the drain tasks unblock
///    even when a grandchild still holds the write end. The worst case is a
///    bounded, typed failure — never an unbounded wait.
///
/// This type exists so those invariants are structural rather than remembered.
/// New engines that shell out MUST call `run` instead of driving `Process`
/// directly; that is what stops #91/#165 recurring a third time.
public enum SubprocessRunner {

    /// Thread-safe "the child really exited" latch, flipped by the
    /// terminationHandler (which fires on a private queue). The watchdog loops
    /// on this instead of `Process.isRunning`, whose spurious `false` right
    /// after `run()` under load skipped the watchdog entirely and left an
    /// unbounded `waitUntilExit()` — the 1-hour CI hang of #91.
    final class ExitLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var exited = false
        var isSet: Bool { lock.withLock { exited } }
        func set() { lock.withLock { exited = true } }
    }

    /// Spawn `executable`, drain both pipes concurrently, and return once the
    /// child exits or `timeout` elapses.
    ///
    /// - Throws: `TranscriptionError` if the child cannot be launched, or if it
    ///   had to be killed at the deadline.
    /// - Returns: `(exit status, stdout, stderr)`.
    public static func run(
        executable: String, arguments: [String], timeout: TimeInterval, backend: String
    ) async throws -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        // Installed BEFORE run() so an instant exit can never miss the latch.
        let exited = ExitLatch()
        process.terminationHandler = { _ in exited.set() }

        do {
            try process.run()
        } catch {
            throw TranscriptionError(
                backend: backend,
                message: "cannot launch '\(executable)': \(error.localizedDescription)",
                underlying: error)
        }

        // Invariant 1: reader tasks start now — before any wait — so a chatty
        // child can never fill the pipe buffer and wedge us.
        async let outData = Task.detached {
            outPipe.fileHandleForReading.readDataToEndOfFile()
        }.value
        async let errData = Task.detached {
            errPipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        // Invariant 2: this loop exits ONLY via the exit latch (the child is
        // really gone) or the deadline kill — never via a racy liveness read,
        // so waitUntilExit() below is bounded on both paths.
        while !exited.isSet {
            if Date() > deadline {
                timedOut = true
                process.terminate()
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !exited.isSet {
                    kill(process.processIdentifier, SIGKILL)
                }
                // A grandchild may still hold the pipe write end — closing our
                // read ends unblocks the drain tasks so a killed child can
                // never wedge the host (#51 verify M4).
                try? outPipe.fileHandleForReading.close()
                try? errPipe.fileHandleForReading.close()
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        process.waitUntilExit()

        let stdout = String(decoding: await outData, as: UTF8.self)
        let stderr = String(decoding: await errData, as: UTF8.self)
        if timedOut {
            throw TranscriptionError(
                backend: backend,
                message: "'\(executable)' timed out after \(Int(timeout))s and was terminated",
                underlying: nil)
        }
        return (process.terminationStatus, stdout, stderr)
    }
}
