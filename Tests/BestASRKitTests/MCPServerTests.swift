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
}
