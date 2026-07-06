## Context

#20 移除 mlx-audio 後只剩兩個 Whisper 引擎；#35 要求恢復跨家族競擇。FluidAudio 0.15.4 已為 diarization exact-pin 於 Package.swift，其 `AsrManager` 提供 Parakeet TDT CoreML 推論——零新依賴。#36 的 AudioNormalizer 已保證 Engine seam 收 16 kHz mono。

## Goals / Non-Goals

**In scope**：ParakeetEngine conformer、BackendID 第三成員、grid live rows、router/benchmark/CLI 全鏈納入、跨家族 metric 統一 normalize。
**Out of scope**：mlx-audio 復活、中文家族（Qwen3-ASR）、external-process 協定、reference rows 語意變更、effort profile 對 Parakeet 的差異化。

## Decisions

### D1 — Engine seam 不動，ParakeetEngine 是純 conformer

`Engine` protocol（id / isAvailable / transcribeRaw）維持原樣。ParakeetEngine 隱藏：FluidAudio `AsrManager` 生命週期（per-instance CreateOnceStore 快取，同 WhisperKitEngine #7 慣例）、模型按需下載、`ASRResult` → `RawTranscription` 映射（token/segment timestamps → RawSegment start/end/text/confidence）。Deletion test：刪掉即回 Whisper-only，非 pass-through——seam 深度足夠。

### D2 — BackendID 命名 `fluid-parakeet`

rawValue 用 `fluid-parakeet`（廠商前綴），不用裸 `parakeet`：ModelGrid 的 mlx-audio parakeet reference row 仍存在，backend 欄位必須可區分「FluidAudio CoreML 可跑的 parakeet」與「mlx-audio reference 的 parakeet」。CaseIterable 順序 append 尾端（store 枚舉順序穩定性）。

### D3 — Availability 語意：runtime 恆真、模型下載惰性

`isAvailable()` 回 true（FluidAudio 編譯進 binary，同 WhisperKit 姿態）；模型於首次 transcribeRaw 下載（AsrModels.downloadAndLoad）。下載失敗 → TranscriptionError fail-loud（不降級、不静默跳過），與 asr-engine spec「Availability detection is graceful / Transcription failure is surfaced」一致。

### D4 — Grid rows：live parakeet 與 reference 並存

新增 `backend: "fluid-parakeet", family: "parakeet", size: "0.6b"（v2/v3 依 FluidAudio 0.15.4 實際提供）, priority: 1, verified: true`（實測後標）。mlx-audio rows 一律不動。Router 枚舉「有 engine 的 backend」自然涵蓋新 rows——現有濾除機制（#20 測試鎖定）不需改。

### D5 — 跨家族 metric 可比性走既有 TextNormalizer

benchmark 對每個 hypothesis 統一 normalize 後計 WER/CER。Parakeet 輸出的 punctuation/casing 慣例與 Whisper 不同，normalizer 已抹平大小寫/標點/空白。若殘餘偏差（ITN 數字格式等）在實測中顯著，記為 benchmark spec 的已知限制——不在本 change 引入 per-family normalizer。

### D6 — Stacked branch on #36

實作 branch base = idd/36-mp3-input-normalization：Parakeet 同樣預期 16 kHz mono，AudioNormalizer 保證來自 #36。#36 先 merge 則 rebase 到 main。

## Risks / Trade-offs

- **FluidAudio ASR API 形狀風險**：0.15.4 的 AsrManager 公開面若與假設不符（batch-only、無 streaming timestamps），映射層吸收；極端情況（無 per-segment timestamps）退化為單 segment 全文，SRT 品質降——實作首步先 spike API 形狀
- **模型下載體積**：Parakeet TDT ~0.6B CoreML，首跑下載數百 MB；與 WhisperKit 慣例一致，CLI 已有下載中提示慣例
- **Parakeet 語言覆蓋**：v2 英文/v3 歐語，中文缺——benchmark 的 zh corpus 對其量測會很差，router 對 zh 音檔自然不選它（這正是機制正確運作的證明，非缺陷）
- **競擇公平性**：單一家族單一尺寸 vs Whisper 六尺寸——candidate 數不對稱不影響「per-(backend,model) measured 排序」的正確性

## Migration Plan

無資料遷移。Store schema 不變（backend 欄位是字串）；既有 benchmark 記錄不受影響。Rollback = revert commits（BackendID case 移除會讓含 fluid-parakeet 的 store rows 變 orphan——router 濾除機制已涵蓋此形狀，#20 先例）。

## Open Questions

（無——unattended 決策已全部內聯為 D1-D6 與 Risks）
