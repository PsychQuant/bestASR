import Foundation

/// A process-lifetime, create-once-per-key cache (#7: WhisperKit pipeline
/// reuse). Storing the creation `Task` — not the value — is what makes
/// concurrent first lookups collapse into a single factory run: the second
/// caller finds the in-flight task and awaits it instead of racing a
/// duplicate creation. A failed task is evicted so the next lookup retries
/// rather than replaying the cached error forever.
///
/// `Value` is deliberately not required to be `Sendable`: WhisperKit's
/// pipeline class predates strict concurrency. Access is serialized by the
/// actor; callers receive a reference they must use as the library intends
/// (the engine performs one transcription at a time per call).
actor CreateOnceStore<Value> {
    private var inFlight: [String: Task<Value, Error>] = [:]

    /// Evict every entry except `key` — the benchmark sweeps models
    /// sequentially through one process, and without eviction a full sweep
    /// keeps every CoreML model resident at once (sum-of-models envelope, up
    /// to ~26 GB by the registry's own upper bounds). Keeping only the
    /// current model preserves the warm-up→timed reuse this store exists for
    /// while restoring the old one-model-at-a-time memory envelope. Dropped
    /// pipelines are released by ARC once their transcription finishes.
    func retainOnly(_ key: String) {
        inFlight = inFlight.filter { $0.key == key }
    }

    /// Like retainOnly, but hands back the evicted values so callers owning
    /// external resources (worker processes, #14) can terminate them.
    func retainOnlyReturningEvicted(_ key: String) async -> [Value] {
        var evicted: [Value] = []
        for (existingKey, task) in inFlight where existingKey != key {
            if let value = try? await task.value { evicted.append(value) }
        }
        inFlight = inFlight.filter { $0.key == key }
        return evicted
    }

    func value(
        for key: String, make: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let task = inFlight[key] {
            return try await task.value
        }
        let task = Task { try await make() }
        inFlight[key] = task
        do {
            return try await task.value
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}
