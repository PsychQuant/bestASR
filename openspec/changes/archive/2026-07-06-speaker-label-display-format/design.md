## Context

#54：使用者以 SRT 範例指定 `Speaker 1: ` cue 前綴。現行 `[SPEAKER_1] `（TranscriptWriter.swift `cueText`）與 `SPEAKER_1: `（`renderTXT`）。cli spec :355 與 diarization spec 的輸出格式為 SHALL 級 normative。

## Goals / Non-Goals

**In scope**：TranscriptWriter 顯示映射 + 三格式 colon 統一 + 2 spec deltas + 測試同步。
**Out of scope**：內部 label ID、diarization 引擎、speaker-id 匹配、格式選項、無 diarize 的輸出。

## Decisions

### D1 — 顯示映射放 writer 層，內部 ID 不動

`TranscriptWriter` 新增 `displaySpeaker(_:)`：`^SPEAKER_(\d+)$` → `Speaker \1`；不匹配（enrollment 真名）原樣返回。理由：內部 `SPEAKER_N` ID 是 diarization/store/enrollment 的穩定識別字串（diarization spec SHALL），動它會擾動三個子系統；顯示格式是 writer 的職責。Deletion test：刪掉映射即回機器風格——非 pass-through。

### D2 — 三格式統一 colon 前綴

SRT/VTT 從 `[X] text` 改 `X: text`；txt 已是 colon 只換 label 顯示。單一慣例，使用者範例即驗收。

## Risks / Trade-offs

- 下游 parse 舊 `[SPEAKER_N]` 者 break——spec 同步後即新契約，CHANGELOG 註明
- 真名含 `SPEAKER_` 前綴的病態 case（enrollment 名剛好叫 SPEAKER_9）會被誤映射——regex 錨定完整匹配把風險縮到「真名恰為 SPEAKER_數字」，實務可忽略

## Migration Plan

無資料遷移；輸出格式變更隨版本釋出，CHANGELOG 記 breaking-format note。Rollback = revert commit。

## Open Questions

（無）
