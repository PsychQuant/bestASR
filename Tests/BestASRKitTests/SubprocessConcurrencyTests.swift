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

        let budget: TimeInterval = 1

        func worstElapsed(concurrency: Int) async -> Double {
            let all = await withTaskGroup(of: Double.self) { group in
                for _ in 0..<concurrency {
                    group.addTask {
                        let start = ContinuousClock.now
                        _ = try? await SubprocessRunner.run(
                            executable: script.path, arguments: [], timeout: budget,
                            backend: "test")
                        let d = start.duration(to: .now)
                        return Double(d.components.seconds)
                            + Double(d.components.attoseconds) / 1e18
                    }
                }
                var out: [Double] = []
                for await v in group { out.append(v) }
                return out
            }
            return all.max() ?? 0
        }

        // The property under test is that the deadline does not DEGRADE as
        // concurrency rises — not that it lands on a particular wall-clock
        // number. Asserting an absolute bound made this fail on a loaded 3-core
        // CI runner (4.2x) while passing on an idle 18-core dev box, which
        // measures the machine rather than the code. A same-run single-call
        // baseline cancels out machine speed and ambient load.
        let solo = await worstElapsed(concurrency: 1)
        // Above the core count on purpose — the defect only appears once the
        // blocking drains outnumber the pool's threads — but scaled to the
        // machine, because a fixed 24 is ~1.3x the cores here and ~8x on CI.
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let concurrency = min(24, max(8, cores * 2))
        let loaded = await worstElapsed(concurrency: concurrency)

        // Pre-fix this ratio was 6.6x at concurrency 16 and 18.6x at 32 on an
        // idle machine; after moving the drains off the cooperative pool it is
        // ~1.0x. 3x leaves room for scheduling noise without admitting the bug.
        let ratio = loaded / max(solo, 0.001)
        let detail = String(
            format: "solo=%.2fs loaded=%.2fs (concurrency %d) ratio=%.1fx",
            solo, loaded, concurrency, ratio)
        #expect(ratio < 3.0, "\(detail) — blocking drains are starving the deadline check")
    }
}
