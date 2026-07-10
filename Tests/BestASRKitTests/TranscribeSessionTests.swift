import Foundation
import Testing

@testable import BestASRGUICore
import BestASRKit

/// spec gui-app (#87): the GUI session state machine, driven by injected fake
/// runners — no engines, no audio, no SwiftUI. Completion ordering is gated
/// (never real sleeps racing the scheduler — the #86 CI lesson).
@MainActor
struct TranscribeSessionTests {
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

    private static func request(path: String = "/tmp/in.wav") -> TranscribeRequest {
        TranscribeRequest(
            audioPath: path, requestedLanguage: nil, profileName: "auto", formatName: "srt")
    }

    /// Polls the MainActor phase until it leaves .running (bounded, gate-driven
    /// completions make the wait short and deterministic).
    private func awaitTerminal(_ session: TranscribeSession) async {
        for _ in 0..<2_000 {
            if !session.isRunning { return }
            await Task.yield()
        }
    }

    @Test func `Happy path lands in done with the outcome and preview`() async throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("gui-session-\(UUID().uuidString).srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nhello\n".write(
            to: out, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: out) }

        let session = TranscribeSession(runner: { request in
            TranscribeOutcome(
                outputPath: out.path, format: request.formatName, explanation: "fake route")
        })
        session.start(Self.request())
        #expect(session.isRunning)
        await awaitTerminal(session)

        guard case .done(let completion) = session.phase else {
            Issue.record("expected done, got \(session.phase)")
            return
        }
        #expect(completion.outputPath == out.path)
        #expect(completion.formatName == "srt")
        #expect(completion.explanation == "fake route")
        #expect(completion.preview.contains("hello"))
    }

    @Test func `A thrown core error surfaces verbatim in the failed phase`() async {
        let session = TranscribeSession(runner: { _ in
            throw BestASRError.usage("audio file not found: /tmp/in.wav")
        })
        session.start(Self.request())
        await awaitTerminal(session)
        #expect(session.phase == .failed("audio file not found: /tmp/in.wav"))
    }

    @Test func `Start is single-flight while running`() async {
        let gate = Gate()
        let session = TranscribeSession(runner: { request in
            await gate.wait()
            return TranscribeOutcome(outputPath: request.audioPath, format: "srt", explanation: "")
        })
        session.start(Self.request(path: "/tmp/first.wav"))
        guard case .running(let startedAt) = session.phase else {
            Issue.record("expected running"); return
        }
        session.start(Self.request(path: "/tmp/second.wav"))  // must be a no-op
        #expect(session.phase == .running(startedAt: startedAt))
        await gate.open()
        await awaitTerminal(session)
        guard case .done(let completion) = session.phase else {
            Issue.record("expected done, got \(session.phase)"); return
        }
        // The first request's run finished; the second never started.
        #expect(completion.outputPath == "/tmp/first.wav")
    }

    @Test func `Cancel returns to idle and drops the stale completion`() async {
        let gate = Gate()
        let session = TranscribeSession(runner: { request in
            await gate.wait()  // parked past the cancel
            return TranscribeOutcome(outputPath: request.audioPath, format: "srt", explanation: "")
        })
        session.start(Self.request())
        #expect(session.isRunning)
        session.cancel()
        #expect(session.phase == .idle)
        // Un-park the orphaned run: its completion must NOT resurrect a phase.
        await gate.open()
        for _ in 0..<200 { await Task.yield() }
        #expect(session.phase == .idle)
    }

    @Test func `Reset clears a terminal phase but never an active run`() async {
        let session = TranscribeSession(runner: { _ in
            throw BestASRError.runtime("boom")
        })
        session.start(Self.request())
        await awaitTerminal(session)
        guard case .failed = session.phase else {
            Issue.record("expected failed"); return
        }
        session.reset()
        #expect(session.phase == .idle)

        let gate = Gate()
        let running = TranscribeSession(runner: { request in
            await gate.wait()
            return TranscribeOutcome(outputPath: request.audioPath, format: "srt", explanation: "")
        })
        running.start(Self.request())
        running.reset()  // no-op while running
        #expect(running.isRunning)
        await gate.open()
    }

    @Test func `Options vocabularies track the core types`() {
        #expect(GUIOptions.efforts.first == "auto")
        #expect(GUIOptions.efforts.contains("max"))
        #expect(GUIOptions.efforts.count == 1 + RouterProfile.allCases.count)
        #expect(GUIOptions.formats.contains("srt"))
        #expect(GUIOptions.languages.first == "auto")
        #expect(GUIOptions.requestedLanguage(fromSelection: "auto") == nil)
        #expect(GUIOptions.requestedLanguage(fromSelection: "zh") == "zh")
    }
}
