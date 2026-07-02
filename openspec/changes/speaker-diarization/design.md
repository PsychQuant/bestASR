## Context

FluidAudio 批次 API：`DiarizerModels.downloadIfNeeded()` → `DiarizerManager().initialize(models:)` → `AudioConverter().resampleAudioFile(url)`（16kHz mono Float32）→ `performCompleteDiarization(samples)` → timed speaker segments。平台 macOS 14 == bestASR 最低版。`TranscriptSegment{id,start,end,text,confidence}`；SRT/VTT 由 `TranscriptWriter` 各 render 函式產出。

## Goals / Non-Goals

Goals：cue 級 SPEAKER_N、opt-in、離線後可重複（模型快取）、真實多說話者驗證。Non-goals 見 proposal。

## Decisions

### D1 — 指派演算法（純函式，TDD）

`SpeakerAssigner.assign(segments:turns:) -> [String?]`：對每個 transcription segment，取與其時間區間**重疊長度最大**的 turn 之 speaker；零重疊 → nil（不虛構）；tie → 較早開始的 turn。cue 級粒度 = 使用者裁決；跨 speaker 的長 segment 歸多數方（Whisper segment 邊界本就近似語句邊界，誤差可接受——word 級為 #26 之後的演進空間）。

### D2 — speaker 標籤格式

`SPEAKER_1`-based 連號（FluidAudio 回的 raw id 重新映射為出現序），SRT/VTT 前綴 `[SPEAKER_1] text`、json `"speaker": "SPEAKER_1"`、txt `SPEAKER_1: text`。無 diarize 時輸出 byte-identical 於現行（零回歸鐵律）。

### D3 — 供應鏈邊界（trusted vendor）

FluidAudio pin exact v0.15.4（SPM `.exact`）；CoreML 模型由 SDK 管理自 HF FluidInference org 下載（SDK 內建 revision 管理 + `enforceOffline` flag）——與 #15 的自管 pin 紀律不同層：這裡把 vendor SDK 視為 trust boundary，記錄而非重造其模型下載器。

### D4 — 失敗語意

`--diarize` 但模型下載失敗/引擎錯誤 → **usage/runtime error 明確失敗**（不靜默退化成無 speaker 輸出——使用者顯式要求的能力不可靜默丟）。

### D5 — 驗證語料（零新下載）

`fleurs_ja.wav`/`fleurs_zh.wav` 本身即 3 個不同 speaker 串接、speaker 邊界 = SRT cue 時間（#18 的 deterministic 選句副產品）→ 期望 ≥2 speakers 且切換點貼近 cue 邊界；`jfk.wav` 單 speaker 陰性對照（期望 1）。

## Implementation Contract

- `swift test` 全綠：SpeakerAssigner 單元（重疊/零重疊/tie/跨界多數）、Writer 四格式 speaker 呈現 + 無 speaker byte-identical、segment Codable 相容
- live：`transcribe fleurs_ja.wav --diarize -f srt` 出現 ≥2 個相異 `[SPEAKER_N]` 且切換點與已知邊界誤差 < 2s；`jfk.wav --diarize` 恰 1 speaker；不帶 --diarize 輸出與 main 完全一致
- `spectra validate` 綠
