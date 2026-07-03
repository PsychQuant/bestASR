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

## 6. Verify fixes（wf_3eff5bd3-a14）

- [x] 6.1 cli MODIFIED delta 以現行 spec 原文為底重寫（首版憑記憶發明了「stdout」——現行 spec 本就正確描述 derived-file；MODIFIED delta 必須抄現行原文再改）
- [x] 6.2 D4 soft-failure：全 nil 指派 fail-loud（guard + spec scenario + seam 測試）
- [x] 6.3 CommandCore 注入縫 `diarizer:`（預設 = 真引擎）——diarize 路徑膠水可測：標籤流通/全空丟錯/flag off 永不觸酸學層（spy）
- [x] 6.4 VTT/JSON no-speaker byte-pin（「四格式 byte-identical」宣稱補齊為真）
- [x] 6.5 epsilon tie（1e-9——Double 精確 == 會被 ULP 打穿「取早」保證）
- [x] 6.6 D5/spec scenario 撤回「3-speaker」前提殘留（design 與**永久 spec** 都改為實際驗證的 2-speaker fixture）；D3 誠實化（SDK 端 revision 管理未經稽核、core-target 連結成本明載）
- [x] 6.7 `scripts/validate-diarization.sh` 可重現驗證（pinned fixture 含 1s 靜音 join——cue 粒度需要邊界斷句，靜音使其確定化；live 三斷言全過：9.30s 切換/jfk 陰性/off 潔淨）
