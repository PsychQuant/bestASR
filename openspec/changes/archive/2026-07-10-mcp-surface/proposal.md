# mcp-surface — bestASR 的第三個消費面（MCP server）

## Why

bestASR 有 CLI（terminal）與 Claude Code plugin（agent skills wrap CLI）兩個消費面（#79 README 已定位）。無 Bash tool 的 MCP client（Claude Desktop 等）無法使用；maintainer 定位（#80）：CLI / plugin / MCP 三位一體。

## What Changes

- 新 executable target `bestasr-mcp`：官方 modelcontextprotocol/swift-sdk（0.12 pin，che-mcps 家族同款）、StdioTransport、直 link BestASRKit
- v1 五 tools：`transcribe` / `recommend` / `list_backends` / `list_models` / `corpus_add`
- README「Install for AI agents」補 MCP 註冊段
- **不含**：`benchmark` tool（timeout 語意惡劣，殘留）；sign/notarize＋mcpb 發佈（v1.1）

## Impact

- Affected specs: ADDED `mcp-surface`
- Affected code: Package.swift、Sources/bestasr-mcp/（新）、README.md
- 既有 CLI/plugin 行為零改動
