import BestASRKit
import Foundation
import MCP

/// bestASR's MCP surface (#80, spec mcp-surface): a long-lived stdio server
/// linking BestASRKit directly — engine pipeline caches (CreateOnceStore)
/// persist across tool calls, so the second transcription never reloads the
/// model. stdout carries JSON-RPC exclusively; every human-facing diagnostic
/// goes to stderr.
public actor BestASRMCPServer {
    let core: CommandCore
    let server: Server

    public init(core: CommandCore = .live()) {
        self.core = core
        self.server = Server(
            name: "bestasr-mcp",
            version: BestASRVersion.current,
            capabilities: .init(tools: .init())
        )
    }

    public func run() async throws {
        await registerHandlers()
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }

    // MARK: - Tools (internal so tests enumerate + cross-check dispatch)

    static func defineTools() -> [Tool] {
        [
            Tool(
                name: "transcribe",
                description: "Transcribe an audio file with the best measured backend/model for "
                    + "this machine (benchmark-driven routing). Supports context biasing "
                    + "(top-down / prompt biasing: domain vocabulary, names) via context_dir "
                    + "and speaker diarization. Returns the transcript text plus an "
                    + "explanation of what was selected and why.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "audio_path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to the audio file"),
                        ]),
                        "language": .object([
                            "type": .string("string"),
                            "description": .string("Two-letter language code, or 'auto' (default)"),
                        ]),
                        "format": .object([
                            "type": .string("string"),
                            "description": .string("Output format: txt | srt | vtt | json (default txt)"),
                        ]),
                        "output_path": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Where to write the transcript file; omitted = temporary file, "
                                    + "content returned either way"),
                        ]),
                        "diarize": .object([
                            "type": .string("boolean"),
                            "description": .string("Label cues with acoustic speakers"),
                        ]),
                        "context_dir": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Context documents directory for context biasing "
                                    + "(default: three-layer resolution)"),
                        ]),
                        "profile": .object([
                            "type": .string("string"),
                            "description": .string("Effort profile: auto | low | medium | high | xhigh | max"),
                        ]),
                        "backend": .object([
                            "type": .string("string"),
                            "description": .string("Backend override (default: routed)"),
                        ]),
                        "model": .object([
                            "type": .string("string"),
                            "description": .string("Model override (default: routed)"),
                        ]),
                    ]),
                    "required": .array([.string("audio_path")]),
                ]),
                annotations: .init(readOnlyHint: false, openWorldHint: false)
            ),
            Tool(
                name: "recommend",
                description: "Recommend the best backend/model for an audio file WITHOUT "
                    + "transcribing — measured numbers when benchmark data exists, honest "
                    + "cold-start prior otherwise. Returns JSON.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "audio_path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to the audio file"),
                        ]),
                        "language": .object([
                            "type": .string("string"),
                            "description": .string("Two-letter language code, or 'auto' (default)"),
                        ]),
                        "profile": .object([
                            "type": .string("string"),
                            "description": .string("Effort profile: auto | low | medium | high | xhigh | max"),
                        ]),
                    ]),
                    "required": .array([.string("audio_path")]),
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "list_backends",
                description: "List ASR backend availability on this machine.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "list_models",
                description: "Show the model grid: whisper sizes plus the mlx-audio catalog "
                    + "with priority tiers and pinned revisions.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "corpus_add",
                description: "Register a ground-truth corpus (audio + reference SRT) so future "
                    + "benchmarks can measure accuracy on YOUR material.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "audio_path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to the audio file"),
                        ]),
                        "reference_path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to the reference .srt"),
                        ]),
                        "language": .object([
                            "type": .string("string"),
                            "description": .string("Two-letter language code (en/zh/ja/...)"),
                        ]),
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Corpus name (default: audio filename)"),
                        ]),
                    ]),
                    "required": .array([
                        .string("audio_path"), .string("reference_path"), .string("language"),
                    ]),
                ]),
                annotations: .init(readOnlyHint: false, openWorldHint: false)
            ),
        ]
    }

    func registerHandlers() async {
        let tools = Self.defineTools()
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return CallTool.Result(content: [.text("server unavailable")], isError: true)
            }
            return await self.execute(name: params.name, arguments: params.arguments ?? [:])
        }
    }

    /// Dispatch — every failure becomes a loud tool error; the server loop
    /// never dies on a bad call (spec mcp-surface: errors are loud and typed).
    func execute(name: String, arguments: [String: Value]) async -> CallTool.Result {
        do {
            let text = try await dispatch(name: name, arguments: arguments)
            return CallTool.Result(content: [.text(text)], isError: false)
        } catch {
            let message: String
            if let t = error as? TranscriptionError {
                message = "[\(t.backend)] \(t.message)"
            } else {
                message = String(describing: error)
            }
            return CallTool.Result(content: [.text(message)], isError: true)
        }
    }

    func dispatch(name: String, arguments args: [String: Value]) async throws -> String {
        switch name {
        case "transcribe":
            let audioPath = try requiredString("audio_path", in: args)
            let selection = SelectionRequest(
                profileName: args["profile"]?.stringValue ?? "auto",
                backendOverride: args["backend"]?.stringValue,
                modelOverride: args["model"]?.stringValue,
                requestedLanguage: languageOrNil(args["language"]?.stringValue),
                contextDir: args["context_dir"]?.stringValue
            )
            let format = args["format"]?.stringValue ?? "txt"
            let output = args["output_path"]?.stringValue
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("bestasr-mcp-\(UUID().uuidString).\(format)").path
            let outcome = try await core.transcribe(
                audioPath: audioPath,
                selection: selection,
                formatName: format,
                outputPath: output,
                diarize: args["diarize"]?.boolValue ?? false
            )
            let content = (try? String(contentsOfFile: outcome.outputPath, encoding: .utf8)) ?? ""
            return content + "\n---\n" + outcome.explanation
                + "\ntranscript file: \(outcome.outputPath)"

        case "recommend":
            let audioPath = try requiredString("audio_path", in: args)
            let selection = SelectionRequest(
                profileName: args["profile"]?.stringValue ?? "auto",
                backendOverride: nil,
                modelOverride: nil,
                requestedLanguage: languageOrNil(args["language"]?.stringValue)
            )
            return try await core.recommendJSON(audioPath: audioPath, selection: selection)

        case "list_backends":
            return await core.listBackends()

        case "list_models":
            return core.listModels()

        case "corpus_add":
            let row = try CorpusRegistry.add(
                audioPath: try requiredString("audio_path", in: args),
                referencePath: try requiredString("reference_path", in: args),
                language: try requiredString("language", in: args),
                name: args["name"]?.stringValue,
                store: BenchmarkStore()
            )
            return "registered corpus '\(row.name)' (\(row.language))"

        default:
            throw BestASRError.usage("unknown tool: \(name)")
        }
    }

    private func requiredString(_ key: String, in args: [String: Value]) throws -> String {
        guard let value = args[key]?.stringValue, !value.isEmpty else {
            throw BestASRError.usage("missing required argument: \(key)")
        }
        return value
    }

    /// "auto" and absence both mean nil (detect).
    private func languageOrNil(_ raw: String?) -> String? {
        guard let raw, raw != "auto" else { return nil }
        return raw
    }
}
