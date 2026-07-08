import Foundation

/// Async job tracking for the MCP `transcribe` tool (#86, spec mcp-surface).
///
/// Engine-independent by design: a caller hands `start` an async work closure
/// (the actual transcription), and the registry runs it on a background task,
/// tracks its state, and serves `status` / `awaitResult` to the poll tools.
/// This keeps the async state machine testable without a real engine.
///
/// Completed jobs are retained just long enough to be fetched, then evicted by
/// a time-based check so a long-lived server does not accumulate them (the
/// #43 / mcp-surface F3 leak lesson). In-memory only — a server restart loses
/// all job state (documented v1 limitation).
public actor JobRegistry {
    /// Coarse lifecycle state. `failed` carries the typed error message.
    public enum State: Sendable, Equatable {
        case running
        case done
        case failed(String)
    }

    /// What a result poll returns.
    public enum Outcome: Sendable, Equatable {
        case result(String)   // the rendered transcript reply (same shape the sync path returns)
        case stillRunning     // not done within the wait cap — caller may poll again
        case failed(String)   // typed error message
        case unknown          // no such job (never existed, or already evicted)
    }

    private struct Entry {
        var state: State
        var result: String?
        var completedAt: Date?
    }

    private var jobs: [String: Entry] = [:]
    private let retention: TimeInterval
    private let pollInterval: Duration

    /// - Parameters:
    ///   - retention: how long a completed/failed job stays fetchable before eviction.
    ///   - pollInterval: how often `awaitResult` re-checks a still-running job.
    public init(retention: TimeInterval = 300, pollInterval: Duration = .milliseconds(50)) {
        self.retention = retention
        self.pollInterval = pollInterval
    }

    /// Register + start a background job. Returns its id immediately; the work
    /// runs concurrently. The registry never lets the work's error escape — it
    /// is captured as `.failed`.
    @discardableResult
    public func start(_ work: @Sendable @escaping () async throws -> String) -> String {
        let id = UUID().uuidString
        jobs[id] = Entry(state: .running, result: nil, completedAt: nil)
        Task { [weak self] in
            do {
                let reply = try await work()
                await self?.complete(id, result: reply)
            } catch let error as JobError {
                await self?.fail(id, message: error.message)
            } catch {
                await self?.fail(id, message: String(describing: error))
            }
        }
        return id
    }

    /// Current state, or nil if the job is unknown (never existed / evicted).
    public func status(_ id: String) -> State? {
        evictIfExpired(id)
        return jobs[id]?.state
    }

    /// Bounded server-side wait: returns as soon as the job is terminal, or
    /// `.stillRunning` once `cap` elapses (so this call cannot itself become the
    /// unbounded blocking call it exists to avoid).
    public func awaitResult(_ id: String, cap: Duration) async -> Outcome {
        if let terminal = terminalOutcome(id) { return terminal }
        let deadline = ContinuousClock.now.advanced(by: cap)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)   // releases the actor while waiting
            if let terminal = terminalOutcome(id) { return terminal }
        }
        // Distinguish "still running" from "evicted while we waited".
        return jobs[id] == nil ? .unknown : .stillRunning
    }

    // MARK: - internals

    /// Returns a terminal outcome (result/failed/unknown) or nil if still running.
    private func terminalOutcome(_ id: String) -> Outcome? {
        evictIfExpired(id)
        guard let entry = jobs[id] else { return Outcome.unknown }
        switch entry.state {
        case .running: return nil
        case .done: return .result(entry.result ?? "")
        case .failed(let message): return .failed(message)
        }
    }

    private func complete(_ id: String, result: String) {
        guard jobs[id] != nil else { return }   // evicted mid-flight — drop
        jobs[id]?.state = .done
        jobs[id]?.result = result
        jobs[id]?.completedAt = Date()
    }

    private func fail(_ id: String, message: String) {
        guard jobs[id] != nil else { return }
        jobs[id]?.state = .failed(message)
        jobs[id]?.completedAt = Date()
    }

    private func evictIfExpired(_ id: String) {
        guard let completedAt = jobs[id]?.completedAt else { return }
        if Date().timeIntervalSince(completedAt) >= retention {
            jobs[id] = nil
        }
    }
}

/// A work closure can throw this to carry a typed, user-facing failure message
/// into the job's `.failed` state (mirrors the loud-error discipline of #80).
public struct JobError: Error, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
