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
