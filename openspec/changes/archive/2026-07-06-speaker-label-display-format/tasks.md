## 0. Design traceability

- D1 — 顯示映射放 writer 層，內部 ID 不動 → tasks 1.1, 1.2
- D2 — 三格式統一 colon 前綴 → tasks 1.1, 1.2

## 1. Writer 顯示映射（TDD）

- [x] 1.1 (design D1/D2; spec cli "transcribe command with options" + spec diarization "Cue-level speaker diarization on demand") RED：DiarizationTests（SpeakerRenderingTests）斷言 SRT/VTT cue = `Speaker 1: text`、txt 行 = `Speaker 1: text`、enrollment 真名 = `Alice: text`、JSON speaker 欄位仍為內部 `SPEAKER_1`。先紅（現行方括號/大寫格式）。驗證：目標測試紅、原因正確
- [x] 1.2 GREEN：`TranscriptWriter` 加 `displaySpeaker(_:)`（`^SPEAKER_(\d+)$` → `Speaker \1`，其餘原樣）；`cueText` 改 colon 前綴；`renderTXT` 用同映射。更新既有 `[SPEAKER_N]` 斷言。驗證：全套件綠

## 2. 收尾

- [x] 2.1 CHANGELOG 記輸出格式變更（breaking-format note：舊 `[SPEAKER_N]` parser 需更新）。驗證：條目存在且指向 #54
