import Foundation
import MCP
import Testing

@testable import BestASRMCPCore

/// spec mcp-surface (#80): tool surface + loud errors.
struct MCPServerTests {
    @Test func `The tool list is exactly the seven tools, benchmark excluded`() {
        let tools = BestASRMCPServer.defineTools()
        let names = tools.map(\.name)
        #expect(
            names == [
                "transcribe", "recommend", "list_backends", "list_models", "corpus_add",
                "transcribe_status", "transcribe_result",
            ])
        #expect(!names.contains("benchmark"))  // spec: v1 scope excludes long-running benchmark
        // The two async poll tools observe state; they are read-only (#86).
        for name in ["transcribe_status", "transcribe_result"] {
            #expect(tools.first { $0.name == name }?.annotations.readOnlyHint == true)
        }
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
        #expect(required("transcribe_status") == ["job_id"])
        #expect(required("transcribe_result") == ["job_id"])
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

    /// #86 async job mode: async:true returns a job id immediately (the work
    /// runs in the background), without blocking or erroring on the spot — even
    /// when the audio will ultimately fail.
    @Test func `Async transcribe returns a job id and running status without blocking`() async throws {
        let server = BestASRMCPServer()
        let result = await server.execute(
            name: "transcribe",
            arguments: [
                "audio_path": .string("/nonexistent/async-clip.wav"), "async": .bool(true),
            ])
        #expect(result.isError == false)
        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("expected text content"); return
        }
        let obj =
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String] ?? [:]
        #expect(obj["status"] == "running")
        #expect(obj["job_id"]?.isEmpty == false)
    }

    /// #86: a background job whose audio fails ends up failed — transcribe_result
    /// surfaces it as a loud error, transcribe_status reports failed. (The bad
    /// path fails fast at AudioProber, before any model load.)
    @Test func `A failed async job is loud on result and failed on status`() async throws {
        let server = BestASRMCPServer()
        let start = await server.execute(
            name: "transcribe",
            arguments: [
                "audio_path": .string("/nonexistent/fail-clip.wav"), "async": .bool(true),
            ])
        guard case .text(let startText, _, _) = start.content.first,
            let jobId = (try JSONSerialization.jsonObject(with: Data(startText.utf8))
                as? [String: String])?["job_id"]
        else {
            Issue.record("no job id from async start"); return
        }
        // transcribe_result long-polls until the job is terminal, then errors loud.
        let res = await server.execute(
            name: "transcribe_result", arguments: ["job_id": .string(jobId)])
        #expect(res.isError == true)
        let status = await server.execute(
            name: "transcribe_status", arguments: ["job_id": .string(jobId)])
        #expect(status.isError == false)
        if case .text(let statusText, _, _) = status.content.first {
            #expect(statusText.contains("failed"))
        }
    }

    /// #86: an unknown job id is a loud tool error on both poll tools.
    @Test func `An unknown job id is loud on both poll tools`() async {
        let server = BestASRMCPServer()
        let st = await server.execute(
            name: "transcribe_status", arguments: ["job_id": .string("no-such-job")])
        #expect(st.isError == true)
        let rs = await server.execute(
            name: "transcribe_result", arguments: ["job_id": .string("no-such-job")])
        #expect(rs.isError == true)
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
