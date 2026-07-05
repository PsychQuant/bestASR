## 0. Design traceability

Design decisions map to tasks as follows (lexical anchors for the analyzer):

- D1 — Engine seam 不動，ParakeetEngine 是純 conformer → tasks 1.1, 2.2
- D2 — BackendID 命名 `fluid-parakeet` → task 1.2
- D3 — Availability 語意：runtime 恆真、模型下載惰性 → tasks 2.1, 2.2
- D4 — Grid rows：live parakeet 與 reference 並存 → task 3.1
- D5 — 跨家族 metric 可比性走既有 TextNormalizer → task 4.1
- D6 — Stacked branch on #36 → task 3.2（實作 branch base）

## 1. API spike + engine skeleton

- [ ] 1.1 (design D1) Spike FluidAudio 0.15.4 ASR 公開 API 形狀：確認 AsrManager／AsrModels 的初始化、模型下載入口、轉錄呼叫簽名、輸出型別是否含 per-segment timestamps。產出：ParakeetEngine.swift 頂部 doc comment 記錄 API 對映表（FluidAudio 型別 → RawTranscription 欄位）。驗證：`swift build` 綠 + doc comment 完整
- [ ] 1.2 (design D2; spec asr-engine "Common engine interface") 新增 `BackendID.fluidParakeet = "fluid-parakeet"`（DataModels.swift，append 尾端）；先寫測試斷言 allCases == [whisperKit, whisperCpp, fluidParakeet] 且 rawValue round-trip（RED→GREEN）。驗證：DataModelTests 綠

## 2. ParakeetEngine conformer（TDD）

- [ ] 2.1 (spec parakeet-engine "ParakeetEngine conforms to the Engine seam" + "Model acquisition is lazy and failure is surfaced") RED：ParakeetEngineTests — (a) id == .fluidParakeet；(b) isAvailable() == true；(c) 以注入 seam（同 WhisperKitEngine pipelineFactory 慣例）spy 斷言 transcribeRaw 把 FluidAudio 輸出映射為 RawTranscription（start/end/text 對映、confidence 缺省 nil）；(d) 模型載入失敗 → TranscriptionError 含 backend 名。驗證：4 tests 先紅
- [ ] 2.2 (design D1/D3) GREEN：實作 ParakeetEngine（pipelineFactory 注入、CreateOnceStore per-model 快取同 #7 慣例、AsrManager 生命週期封裝、fail-loud 映射）。驗證：2.1 全綠 + 全套件綠
- [ ] 2.3 (spec asr-engine "Common engine interface"：三 backend 枚舉) Engine registry / CommandCore 接線：engine(for:) dispatch 涵蓋 .fluidParakeet；`list-backends` 顯示第三行。驗證：CLITests / BackendEngineTests 更新後綠

## 3. Grid + routing（TDD）

- [ ] 3.1 (design D4; spec model-grid "Full-family catalog"（live fluid-parakeet rows）) ModelGrid 新增 live fluid-parakeet row(s)（family parakeet、size 依 1.1 spike 實際提供、priority 1、verified 待 4.1 實測後翻真）；測試斷言 live 與 reference parakeet rows 並存且 backend id 可區分、15 家族 reference 完整不動。驗證：ModelGridTests 綠
- [ ] 3.2 (design D6 依賴序; spec asr-routing "Rank candidates by measured benchmark data") Router 候選枚舉涵蓋 fluid-parakeet：測試 (a) 有 measured 記錄時跨家族依 error_rate/rtf 排序、fluid-parakeet 可勝出；(b) 無 zh 覆蓋時 zh 請求自然排 Whisper 前；(c) mlx-audio reference 仍被濾除（#20 鎖定測試不退化）。驗證：RouterTests 綠

## 4. Benchmark + 實測 + specs

- [ ] 4.1 (design D5; spec benchmark "Compute accuracy metric selected by language") BenchmarkRunner 將 fluid-parakeet 納入量測矩陣（同一 corpora、同一 TextNormalizer 後計 WER/CER）；本機實跑一輪 en corpus 確認 record 落 store（backend 欄位 fluid-parakeet）、`recommend` 對 en 音檔能引用其 measured 證據。實測後把 3.1 的 verified 翻真。驗證：BenchmarkTests 綠 + 實跑輸出貼 PR
- [ ] [P] 4.2 README backend 表格與 CLI help 文案更新（--backend 值域、第三 backend 說明、Parakeet 語言覆蓋註記）。驗證：docs 與 `bestasr list-backends` 輸出一致
- [ ] [P] 4.3 開 2 個 follow-up issues：(a) 中文 high-value 家族（Qwen3-ASR via MLX-Swift）評估；(b) external-process engine 協定（長尾家族）。各附本 change 的 design D1-D6 連結。驗證：issue URLs 記入 PR body
