import Foundation
import Testing
@testable import BestASRKit

/// Semantics for the pipeline cache (#7): one creation per key for the
/// process lifetime, concurrent callers deduplicated, failures not poisoning.
struct CreateOnceStoreTests {
    actor Counter {
        var count = 0
        func bump() -> Int {
            count += 1
            return count
        }
    }

    @Test func `Second lookup reuses the first value without re-creating`() async throws {
        let store = CreateOnceStore<Int>()
        let counter = Counter()
        let first = try await store.value(for: "tiny") { await counter.bump() }
        let second = try await store.value(for: "tiny") { await counter.bump() }
        #expect(first == 1)
        #expect(second == 1)  // same value — factory ran once
        #expect(await counter.count == 1)
    }

    @Test func `Concurrent lookups for the same key run the factory once`() async throws {
        let store = CreateOnceStore<Int>()
        let counter = Counter()
        async let a = store.value(for: "tiny") {
            try? await Task.sleep(nanoseconds: 20_000_000)  // widen the race window
            return await counter.bump()
        }
        async let b = store.value(for: "tiny") { await counter.bump() }
        let (x, y) = (try await a, try await b)
        #expect(x == y)
        #expect(await counter.count == 1)
    }

    @Test func `Distinct keys create distinct values`() async throws {
        let store = CreateOnceStore<Int>()
        let counter = Counter()
        let tiny = try await store.value(for: "tiny") { await counter.bump() }
        let base = try await store.value(for: "base") { await counter.bump() }
        #expect(tiny != base)
        #expect(await counter.count == 2)
    }

    @Test func `A failed creation does not poison the key`() async throws {
        struct Boom: Error {}
        let store = CreateOnceStore<Int>()
        let counter = Counter()
        await #expect(throws: Boom.self) {
            _ = try await store.value(for: "tiny") { throw Boom() }
        }
        // Retry after failure re-runs the factory instead of replaying the error.
        let value = try await store.value(for: "tiny") { await counter.bump() }
        #expect(value == 1)
    }
}
