# Design — mcp-surface

## D1: Native target 直 link BestASRKit（不 spawn CLI）

MCP server 是長駐 process——`CreateOnceStore` pipeline 快取跨呼叫存活，第二次 transcribe 零模型載入。spawn CLI 每呼叫重載模型（數十秒），對互動 agent 不可用。次要：強型別、與 che-mcps 家族同模式。

## D2: v1 tool 面

| Tool | 對映 | 註記 |
|------|------|------|
| `transcribe` | CommandCore transcribe 路徑 | audio_path 必填；language/format/diarize/context_dir/profile/backend/model 選填；回 transcript 文字＋所選 backend/model |
| `recommend` | Router | 回 JSON recommendation |
| `list_backends` | Engine availability | readOnly |
| `list_models` | ModelGrid | readOnly |
| `corpus_add` | CorpusRegistry | audio+reference 必填 |

`benchmark` 不進 v1：全網格數十分鐘 vs MCP tool timeout。殘留（job-handle 模式再議）。

## D3: 發佈 v1 = build-from-source

`swift build -c release` 產 `bestasr-mcp`；README 記 stdio 註冊（claude mcp add / Claude Desktop config）。sign/notarize＋mcpb＋plugin .mcp.json 殘留 v1.1（TCC 面低，ad-hoc 本機可跑）。

## D4: 錯誤面

TranscriptionError/BestASRError → MCP tool error（isError=true＋訊息）；絕不吞。stdout 保留給 JSON-RPC（stdio transport），所有人類訊息走 stderr。
