## Why

專有名詞、人名、領域術語是本機 ASR 最常錯的地方，而使用者手上往往就有相關文件（講義、名單、術語表）。目前 bestASR 沒有任何機制利用這些文件：`TranscribeOptions` 只有 model / quantization / language，校對只能全手動。Issue #3 定義了 context 校準功能（兩條路徑：解碼期 prompt biasing、agent 事後校對），issue #4 定義了承載 agent 路徑的 Claude plugin marketplace。兩者共享同一份 `context.json` 契約——使用者明確指示合一設計（分開必然 schema 漂移），本 change 一次交付。

## What Changes

- **新增 context 資料夾機制**（三層解析：`--context-dir` flag > 工作目錄 `bestasr-context/` > 全域家目錄 context 資料夾，first-hit wins）；資料夾空或不存在時行為零改變。
- **新增 `context.json` schema v1**（version / language / terms / names{name,aliases,role} / phrases / notes）——core 與 plugin 的共同契約；names 同時服務 prompt biasing 與 SRT speaker 軸。
- **Prompt rendering**：context 內容 render 成自然語言詞彙清單（非 JSON），優先序 names → terms → phrases，約 200 token 預算，截斷項記錄並由 `--explain` 揭露。
- **Core 額外輸入面**：資料夾內 `.txt` / `.md` 詞表（一行一詞）併入 terms（no-agent fallback）；pdf / docx 等格式冷拒但大聲提示改跑 context-ingest skill。
- **Engine 管線**：`TranscribeOptions` 增 optional prompt 欄位；WhisperKit 走 decode options 的 prompt 機制、whisper-cli 走 prompt 旗標；engines 不知道資料夾存在（保持笨）。
- **Benchmark ±context 對照**：`benchmark --context-dir` 時每候選量測「無 context / 有 context」兩輪，報表加 delta 欄；快取仍只存 baseline（router 推薦維持 context 中立、`BenchmarkRecord` schema 不變）。
- **Claude plugin marketplace**：repo 新增 marketplace 結構與 `bestasr` plugin，內含兩個 skill——`context-ingest`（agent 讀任意格式文件 → 產出 schema 合法的 context.json）與 `srt-proofread`（依三軸對齊契約校對 SRT：cue 為單位、時間碼不可變、speaker 用 names、輸出 per-cue diff）。
- **SRT 三軸對齊契約入 spec**（講話的人 / 時間點 / 內容）——normative 規則由新 capability 持有，plugin skill 引用之。

## Non-Goals

範圍排除記錄於 design.md 的 Goals / Non-Goals（core 不解析 pdf/docx、不做 diarization、不做 MCP server 形態、快取不存 context-biased 數據、不內建 LLM 呼叫等）。

## Capabilities

### New Capabilities

- `context-calibration`: context 資料夾解析、context.json schema 契約、詞表 fallback、prompt rendering（優先序 + 預算 + 截斷記錄）、explain 揭露、SRT 三軸對齊契約、空資料夾零影響。
- `plugin-marketplace`: repo 作為可安裝的 Claude Code plugin marketplace；bestasr plugin 打包 context-ingest 與 srt-proofread 兩個 skill；plugin 版本與 app 版本同步。

### Modified Capabilities

- `asr-engine`: transcribe options 契約增 optional prompt；engines 將 prompt 轉交各自 backend 的 prompt 機制。
- `cli`: `transcribe` / `recommend` / `benchmark` 增 `--context-dir`；explain 揭露 context 使用（注入詞彙、截斷項、被忽略檔案）。
- `benchmark`: 新增 context-biasing delta 量測（±context 兩輪、delta 報表、快取只存 baseline）。

## Impact

- Affected specs: context-calibration（新）、plugin-marketplace（新）、asr-engine、cli、benchmark（修改）；asr-routing、system-detection、transcript-output 不變。
- Affected code:
  - New:
    - Sources/BestASRKit/Context/ContextSchema.swift
    - Sources/BestASRKit/Context/ContextLoader.swift
    - Sources/BestASRKit/Context/PromptRenderer.swift
    - Tests/BestASRKitTests/ContextTests.swift
    - .claude-plugin/marketplace.json
    - plugins/bestasr/.claude-plugin/plugin.json
    - plugins/bestasr/skills/context-ingest/SKILL.md
    - plugins/bestasr/skills/srt-proofread/SKILL.md
  - Modified:
    - Sources/BestASRKit/Models/DataModels.swift
    - Sources/BestASRKit/Engines/Engine.swift
    - Sources/BestASRKit/Engines/WhisperKitEngine.swift
    - Sources/BestASRKit/Engines/WhisperCppEngine.swift
    - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
    - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
    - Sources/BestASRKit/CommandCore.swift
    - Sources/bestasr/BestASRCommand.swift
    - Tests/BestASRKitTests/CLITests.swift
    - Tests/BestASRKitTests/BenchmarkTests.swift
    - Tests/BestASRKitTests/EngineTests.swift
    - README.md
  - Removed: (none)
- Dependencies: 無新增 SPM 相依（Context 模組全用 Foundation；plugin 為純 markdown skill）。
