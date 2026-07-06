## Why

#55：使用者提供 Jobs & Gates 81 分鐘英文對談＋人工 ground-truth SRT（269 cues），要求納入 benchmark 語料。偵察確認 `corpus add` 路徑現成，唯一缺口在 `SRTParser.referenceText`：speaker-labeled SRT（cue 帶 `Kara Swisher: ` 等前綴）的名字會進 reference 文字，ASR hypothesis 不含它們 → WER 被系統性灌高，speaker-labeled ground truth 全類別不可用。

## What Changes

- `SRTParser` 新增 speaker-prefix 剝除：repeated-prefix heuristic——跨 cues 重複出現的 `Name: ` 前綴集合判定為 speaker 標籤並剝除；單次出現的 colon 文字（正文引言）不誤剝
- benchmark spec 的 SRT reference-parsing requirement 更新（全量重現）
- 語料登記操作（非 code）：檔案搬 `~/.bestasr/corpora/` + `bestasr corpus add --language en`，live 驗證 store row 落地

## Non-Goals

- 不做 81 分鐘語料的 benchmark 切片策略（使用時再議）
- 不動 `TextNormalizer`（速度/大小寫/標點正規化職責不變）
- 不改 SRT cue 解析本身（timecode/block 結構照舊）

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `benchmark`: SRT reference 文字萃取剝除重複 speaker 前綴

## Impact

- Affected specs: benchmark
- Affected code:
  - Modified: Sources/BestASRKit/Benchmark/SRTParser.swift, Tests/BestASRKitTests/MetricsTests.swift（SRTParserTests）
  - New: (none)
