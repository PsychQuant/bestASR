## Context

FluidAudio 批次 API：`DiarizerModels.downloadIfNeeded()` → `DiarizerManager().initialize(models:)` → `AudioConverter().resampleAudioFile(url)`（16kHz mono Float32）→ `performCompleteDiarization(samples)` → timed speaker segments。平台 macOS 14 == bestASR 最低版。`TranscriptSegment{id,start,end,text,confidence}`；SRT/VTT 由 `TranscriptWriter` 各 render 函式產出。

## Goals / Non-Goals

Goals：cue 級 SPEAKER_N、opt-in、離線後可重複（模型快取）、真實多說話者驗證。Non-goals 見 proposal。

## Decisions

### D1 — 指派演算法（純函式，TDD）

`SpeakerAssigner.assign(segments:turns:) -> [String?]`：對每個 transcription segment，取與其時間區間**重疊長度最大**的 turn 之 speaker；零重疊 → nil（不虛構）；tie → 較早開始的 turn。cue 級粒度 = 使用者裁決；跨 speaker 的長 segment 歸多數方（Whisper segment 邊界本就近似語句邊界，誤差可接受——word 級為 #26 之後的演進空間）。

### D2 — speaker 標籤格式

`SPEAKER_1`-based 連號（FluidAudio 回的 raw id 重新映射為出現序），SRT/VTT 前綴 `[SPEAKER_1] text`、json `"speaker": "SPEAKER_1"`、txt `SPEAKER_1: text`。無 diarize 時輸出 byte-identical 於現行（零回歸鐵律）。

### D3 — 供應鏈邊界（trusted vendor，如實記載信任範圍）

FluidAudio pin exact v0.15.4（SPM `.exact`——SOURCE 已 pin）；CoreML 模型 WEIGHTS 由 SDK 於執行期自 HF FluidInference org 下載。**誠實邊界（verify DA 校準）**：SDK 端的模型 revision 管理與 `enforceOffline` 能力**未經本 repo 稽核**——此處的信任是「對 vendor SDK 整體」而非「已驗證的機制」；in-repo 模型 checksum 為可選強化（#26 前評估）。另一接受成本：FluidAudio 連進 BestASRKit core target（所有 consumer 都連結，即使不用 --diarize）——opt-in 是 runtime 行為非 build 依賴，最小佈局下接受。

### D4 — 失敗語意

`--diarize` 但模型下載失敗/引擎錯誤 → **usage/runtime error 明確失敗**（不靜默退化成無 speaker 輸出——使用者顯式要求的能力不可靜默丟）。

### D5 — 驗證語料（實作中自我修正）

原案「fleurs_ja/zh = 3 speaker 串接」在驗證時被推翻：FLEURS TSV **無 speaker 欄**，「相異句首錄音」不保證異人（實查 ja 三句全 MALE——聚為同一人可能即正確行為）。修正後 fixture：**同一句（id 1566）的 MALE+FEMALE 雙錄音串接**（定義上異人、聲學最可分；兩句間插 1s 靜音——cue 級指派只能在轉寫斷句處顯示換手，靜音保證邊界斷句（真實換手處本就常停頓，fixture 使其確定化）；wav digest `5c29dfde0214…`、換手邊界 9.30s（女聲 cue 起點 ≈10.30s））→ 兩 cue 恰在邊界切換 SPEAKER_1→SPEAKER_2 ✓；`jfk.wav` 陰性對照恰 1 speaker ✓。可重現：`scripts/validate-diarization.sh`（pinned 供應鏈同 fetch-corpora 紀律）。

## Implementation Contract

- `swift test` 全綠：SpeakerAssigner 單元（重疊/零重疊/tie/跨界多數）、Writer 四格式 speaker 呈現 + 無 speaker byte-identical、segment Codable 相容
- live：`transcribe fleurs_ja.wav --diarize -f srt` 出現 ≥2 個相異 `[SPEAKER_N]` 且切換點與已知邊界誤差 < 2s；`jfk.wav --diarize` 恰 1 speaker；不帶 --diarize 輸出與 main 完全一致
- `spectra validate` 綠
