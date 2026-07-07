import Foundation
import MCP
import Testing

@testable import BestASRMCPCore

/// spec mcp-surface (#80): tool surface + loud errors.
struct MCPServerTests {
    @Test func `The v1 tool list is exactly the five tools, benchmark excluded`() {
        let names = BestASRMCPServer.defineTools().map(\.name)
        #expect(
            names == ["transcribe", "recommend", "list_backends", "list_models", "corpus_add"])
        #expect(!names.contains("benchmark"))  // spec: v1 scope excludes long-running benchmark
    }

    @Test func `Required arguments are declared in the schemas`() throws {
        let tools = BestASRMCPServer.defineTools()
        func required(_ name: String) -> [String] {
            guard let tool = tools.first(where: { $0.name == name }),
                case .object(let schema) = tool.inputSchema,
                case .array(let req) = schema["required"] ?? .null
            else { return [] }
            return req.compactMap(\.stringValue)
        }
        #expect(required("transcribe") == ["audio_path"])
        #expect(required("recommend") == ["audio_path"])
        #expect(required("corpus_add") == ["audio_path", "reference_path", "language"])
    }

    @Test func `An unknown tool fails loud, not silent`() async {
        let server = BestASRMCPServer()
        let result = await server.execute(name: "no_such_tool", arguments: [:])
        #expect(result.isError == true)
    }

    @Test func `A missing required argument names the argument`() async {
        let server = BestASRMCPServer()
        let result = await server.execute(name: "transcribe", arguments: [:])
        #expect(result.isError == true)
        if case .text(let message, _, _) = result.content.first {
            #expect(message.contains("audio_path"))
        } else {
            Issue.record("expected a text error content")
        }
    }

    @Test func `A nonexistent audio path becomes a tool error naming the path`() async {
        // spec scenario: Missing audio file — the reply is a tool error naming
        // the path, and the server keeps serving (no crash).
        let server = BestASRMCPServer()
        let result = await server.execute(
            name: "recommend",
            arguments: ["audio_path": .string("/nonexistent/clip.wav")])
        #expect(result.isError == true)
        if case .text(let message, _, _) = result.content.first {
            #expect(message.contains("/nonexistent/clip.wav") || message.contains("not"))
        }
        // still serving: a second call works
        let second = await server.execute(name: "list_models", arguments: [:])
        #expect(second.isError == false)
    }

    /// verify findings F1/F2: transcribe MUST be single-flight so concurrent MCP
    /// requests can't overlap the single-model engine. Guards the SingleFlight
    /// gate directly — actor reentrancy defeated the naive "actor serializes it"
    /// assumption, so the gate is the real invariant to lock in.
    @Test func `SingleFlight runs operations strictly one at a time`() async {
        let gate = SingleFlight()
        let tracker = ConcurrencyTracker()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try? await gate.run {
                        await tracker.enter()
                        // Yield repeatedly: if serialization were broken, a
                        // second operation would interleave here and bump the
                        // observed concurrency above 1.
                        for _ in 0..<8 { await Task.yield() }
                        await tracker.leave()
                    }
                }
            }
        }
        #expect(await tracker.maxConcurrent == 1)
        #expect(await tracker.completed == 16)
    }
}

/// Records the peak number of operations running at once.
actor ConcurrencyTracker {
    private var current = 0
    private(set) var maxConcurrent = 0
    private(set) var completed = 0

    func enter() {
        current += 1
        maxConcurrent = max(maxConcurrent, current)
    }

    func leave() {
        current -= 1
        completed += 1
    }
}
