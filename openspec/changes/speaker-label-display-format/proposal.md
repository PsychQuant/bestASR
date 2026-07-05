## Why

使用者以 SRT 範例指定 diarization 輸出格式（#54）：cue 前綴須為人類可讀的 `Speaker 1: `。現行為機器風格 `[SPEAKER_1] `（SRT/VTT）與 `SPEAKER_1: `（txt），與需求不符——「speaker 那邊原本沒設定」屬實，顯示格式從未依使用者需求設計。

## What Changes

- `TranscriptWriter` 顯示層映射：`SPEAKER_N`（內部 ID）→ `Speaker N`（顯示），SRT/VTT/txt 一律 `Speaker N: ` colon 前綴；enrollment 真名（#26）沿用 `Name: `
- 內部 speaker ID（`SPEAKER_1`-based ordinals）、diarization 引擎、store、enrollment 匹配**完全不動**
- cli 與 diarization 兩個 living spec 的 normative 輸出格式文字同步

## Non-Goals

- 不加 `--speaker-format` 選項（範例語氣為「要求」，直接改預設）
- 不改內部 label 生成 / 不動 diarization 引擎與 speaker-id 匹配
- 「diarization off 輸出 byte-identical」不變量維持

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `cli`: transcribe --diarize 的三格式前綴文字改為 `Speaker N: `
- `diarization`: 顯示層 label 格式 normative 文字更新（內部 ordinal ID 不變）

## Impact

- Affected specs: cli, diarization
- Affected code:
  - Modified: Sources/BestASRKit/Output/TranscriptWriter.swift, Tests/BestASRKitTests/DiarizationTests.swift
  - New: (none)
  - Removed: (none)
