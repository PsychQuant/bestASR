## 1. 依賴與型別

- [x] 1.1 Package.swift：FluidAudio `.exact("0.15.4")` 進 BestASRKit
- [x] 1.2 `TranscriptSegment.speaker: String?`（預設 nil；json 僅在非 nil 時輸出）

## 2. TDD — 純函式與呈現

- [x] 2.1 RED：SpeakerAssigner 單元（最大重疊/零重疊 nil/tie 取早/跨界多數/標籤依出現序重映射）
- [x] 2.2 RED：TranscriptWriter 四格式 speaker 呈現 + 無 speaker byte-identical
- [x] 2.3 GREEN：`Diarize/SpeakerAssigner.swift` + Writer 修改

## 3. 引擎與管線

- [x] 3.1 `Diarize/DiarizationEngine.swift`（FluidAudio wrapper：downloadIfNeeded → resample → performCompleteDiarization → [SpeakerTurn] 依出現序重映射）
- [x] 3.2 CommandCore.transcribe 接 `diarize: Bool`（D4 fail-loud）；BestASRCommand `--diarize` flag
- [x] 3.3 全套件綠

## 4. 真實驗證（D5）

- [x] 4.1 多說話者驗證 — **驗證設計修正**：FLEURS TSV 無 speaker 欄，原「不同句首錄音」不保證異人（實查三句全 MALE、被聚為同一人可能為正確行為）；改用**同句雙錄音（MALE+FEMALE，定義上異人）**構造保證 2-speaker 檔 → 兩 cue 恰在已知 9.30s 邊界切換 SPEAKER_1→SPEAKER_2 ✓；附帶活例：單 cue 跨兩 speaker 時依 D1 多數重疊歸戶
- [x] 4.2 `jfk.wav --diarize`：恰 1 speaker（陰性對照）
- [x] 4.3 不帶 --diarize：輸出與 main byte-identical

## 5. 收尾

- [x] 5.1 CHANGELOG（assert-after-replace）；`spectra validate` 綠
