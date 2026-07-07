## ADDED Requirements

### Requirement: MCP server exposes bestASR over stdio

The system SHALL provide an executable `bestasr-mcp` speaking MCP over stdio (official swift-sdk), linking BestASRKit directly so engine pipeline caches persist across tool calls within one server process. Human-facing diagnostics SHALL go to stderr only; stdout carries JSON-RPC exclusively.

#### Scenario: Server starts and lists tools

- **WHEN** an MCP client connects over stdio and requests the tool list
- **THEN** exactly the v1 tools are listed: transcribe, recommend, list_backends, list_models, corpus_add

#### Scenario: Second transcription reuses the warm pipeline

- **WHEN** two transcribe calls for the same backend/model arrive in one server session
- **THEN** the second call does not reload the model (CreateOnceStore reuse)

### Requirement: Tool errors are loud and typed

Tool execution failures SHALL be returned as MCP tool errors carrying the underlying typed message (TranscriptionError/BestASRError), never swallowed and never crashing the server loop.

#### Scenario: Missing audio file

- **WHEN** transcribe is called with a nonexistent audio_path
- **THEN** the reply is a tool error naming the path, and the server keeps serving

### Requirement: v1 scope excludes long-running benchmark

The v1 tool set SHALL NOT include a benchmark tool; the exclusion and its reason (tool-timeout semantics) SHALL be documented in the design record.

#### Scenario: Benchmark is absent from the tool list

- **WHEN** the tool list is requested
- **THEN** no benchmark tool appears
