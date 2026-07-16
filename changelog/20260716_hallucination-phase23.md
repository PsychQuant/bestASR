# 2026-07-16 — 幻覺過濾 Phase 2+3（#100 confidence-gated full 模式、#101 decode knobs）

## 出貨（PR #102，cluster：兩案共享 WhisperKitEngine/TranscribeOptions/CLI）

- **`--hallucination-filter full`（#100）**：denylist 之上加 confidence gating——
  openai-whisper 語意的聯合靜音規則（`noSpeechProb > 0.6` **且** `avgLogprob < -1.0`）
  與重複規則（`compressionRatio > 2.4`）。`RawSegment`/`TranscriptSegment` 新增
  optional `noSpeechProb`/`compressionRatio`（WhisperKit 填入；其他 backend 留 nil，
  nil 永不觸發門檻 → `full` 對該 backend 自動退化為 `denylist`，零分支）。
  輸出格式不變（訊號僅供 filter 內部使用）。MCP `hallucination_filter` 參數自動可用 `full`。
- **WhisperKit decode-param knobs（#101）**：`--no-speech-threshold` /
  `--compression-ratio-threshold` / `--logprob-threshold`（WhisperKit 限定；
  未設 = 原廠預設 byte-for-byte）。verify 抓到真 HIGH：ArgumentParser 拒收前導
  dash 值，而 log-prob 定義域恆為負——文件化的空格寫法在整個有意義範圍不可用；
  以 `parsing: .unconditional` 修復 + 以真實 `Transcribe` 命令的空格形式回歸測試
  （test target 因此連結 executable target）。`chunkingStrategy` 依 issue 原文
  「possibly」明文緩議（residue）。

## 程式檔變更（今日）

- `Sources/BestASRKit/Output/HallucinationFilter.swift` — `.full` 模式 + 具名門檻常數
- `Sources/BestASRKit/{Engines/Engine,Engines/WhisperKitEngine,Models/DataModels}.swift` — 訊號 plumbing + knobs
- `Sources/BestASRKit/CommandCore.swift`、`Sources/bestasr/BestASRCommand.swift` — 三 knob 貫穿 CLI
- `Tests/BestASRKitTests/{HallucinationFullModeTests,DecodeKnobsTests}.swift` — 10 個新測試
- `Package.swift` — test target 連結 executable（CLI parse 回歸測試）
- `README.md` — full 模式 + knobs + deterministic 交互 + CLI-only scope

## 維運

- #100 / #101 已以完整 closing summaries 手動關閉（cluster close）；backlog 歸零。
