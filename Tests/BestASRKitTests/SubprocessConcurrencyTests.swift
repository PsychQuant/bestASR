import Foundation
import Testing

@testable import BestASRKit

/// #165 round 3. The header of `SubprocessRunner` states, as Guarantee 1, that
/// the drains "are detached and blocking; the box (not an `await`) is how the
/// deadline path reads them, so a drain that never returns cannot extend the
/// deadline."
///
/// That is true of *one* drain and false of *many*. `Task.detached` runs on the
/// cooperative thread pool, and `readDataToEndOfFile()` blocks the thread it
/// lands on. Enough concurrent runs and the pool has no thread left to resume
/// `raceCompletion`'s `Task.sleep` continuation — so the deadline check itself
/// stops being scheduled and the budget is exceeded by whatever margin the
/// blocked drains take to clear.
///
/// Measured on an 18-core M5 Max against a 1 s budget, before the fix:
///
/// | concurrency |  1  |  2  |  4  |  8  |  16   |   32   |
/// |-------------|-----|-----|-----|-----|-------|--------|
/// | max elapsed | 1.0 | 1.0 | 1.0 | 1.0 | 6.6 s | 18.6 s |
///
/// Output was never truncated, so Guarantee 5 held throughout — this is purely
/// a deadline-hardness defect. But an unbounded-in-practice wait is the exact
/// failure this whole PR exists to eliminate (#91 → #158 → #165), so it is the
/// same bug in a fourth costume.
@Suite(.serialized)
struct SubprocessConcurrencyTests {
    private func stub(_ body: String) throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bestasr-conc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("stub.sh")
        try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (dir, script)
    }

    @Test func `The deadline holds when many runs are in flight at once`() async throws {
        // Each child emits ~400 KB (well past the 64 KB pipe buffer) and leaves
        // a grandchild holding the write end for 6 s — far beyond the 1 s
        // budget — so every call must take the timeout branch.
        let (dir, script) = try stub(
            "awk 'BEGIN{for(i=0;i<6000;i++) print \"PAYLOAD padding padding padding padding padding padding\"}'\n"
                + "( sleep 6 ) &\n"
                + "exit 0\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        // Above the core count on purpose: the defect only appears once the
        // blocking drains outnumber the pool's threads.
        let concurrency = max(24, ProcessInfo.processInfo.activeProcessorCount + 8)
        let budget: TimeInterval = 1

        let elapsed = await withTaskGroup(of: Double.self) { group in
            for _ in 1...concurrency {
                group.addTask {
                    let start = ContinuousClock.now
                    _ = try? await SubprocessRunner.run(
                        executable: script.path, arguments: [], timeout: budget, backend: "test")
                    let d = start.duration(to: .now)
                    return Double(d.components.seconds)
                        + Double(d.components.attoseconds) / 1e18
                }
            }
            var all: [Double] = []
            for await v in group { all.append(v) }
            return all
        }

        let worst = elapsed.max() ?? 0
        // Generous: the assertion is about order of magnitude, not scheduling
        // jitter. Pre-fix this ran 6-19x over on the same machine.
        let detail = String(
            format: "deadline slipped to %.2fs against a %.0fs budget at concurrency %d",
            worst, budget, concurrency)
        #expect(worst < budget * 3, "\(detail) — blocking drains starve the deadline check")
    }
}
