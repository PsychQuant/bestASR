import Foundation
import Testing

@testable import BestASRKit

/// #165 round 4 CRITICAL. `FileHandle.readDataToEndOfFile()` is an Objective-C
/// API that RAISES `NSFileHandleOperationException` on a closed descriptor, and
/// an ObjC exception cannot be caught by Swift `do`/`catch` — it terminates the
/// process. The drains race `teardown()` by construction (teardown closes the
/// read ends precisely to unblock them), so a drain submitted but not yet
/// started reads an already-closed handle.
///
/// Round 3's move to `DispatchQueue` is what made this reachable: under
/// `Task.detached`, cooperative-pool starvation delayed teardown roughly in step
/// with drain congestion; decoupling them lets teardown run promptly while
/// drains sit backlogged. Reviewers reproduced a process abort in 2 of 4 runs at
/// concurrency 1000.
///
/// If this suite ever regresses, it does not fail — it CRASHES the test
/// process, which is the point.
struct SubprocessDrainSafetyTests {
    @Test func `Draining an already-closed handle yields empty output, not a crash`() throws {
        let pipe = Pipe()
        let handle = pipe.fileHandleForReading
        try handle.close()
        // The legacy API aborts here. This must simply return nothing.
        #expect(SubprocessRunner.drain(handle).isEmpty)
    }

    @Test func `Draining a handle closed concurrently mid-read does not crash`() async throws {
        // Closing the read end while a drain is parked in read(2) is the exact
        // teardown-vs-drain interleaving, rather than the already-closed case.
        for _ in 0..<25 {
            let pipe = Pipe()
            let handle = pipe.fileHandleForReading
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                _ = SubprocessRunner.drain(handle)
                done.signal()
            }
            // No writer ever closes the write end, so the drain blocks; closing
            // the read end under it is what teardown() does.
            try? await Task.sleep(for: .milliseconds(5))
            try? handle.close()
            _ = done.wait(timeout: .now() + .seconds(5))
        }
    }
}
