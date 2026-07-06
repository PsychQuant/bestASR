## 0. Design traceability

- D1 — 兩個獨立 backend，不合併為單一「funasr」backend → tasks 1.1, 1.2
- D2 — String-only 輸出映射為單段全文 raw segment → tasks 1.1, 1.2
- D3 — SenseVoice v1 一律 auto-detect，不猜語言 embed index → tasks 1.1, 1.2
- D4 — 不加 hard language gate（沿 #35） → task 2.1
- D5 — 實測協定（issue acceptance） → task 3.1

## 1. 兩個 Engine conformers（TDD）

- [x] 1.1 (design D1/D2/D3; spec chinese-asr-engines "ParaformerEngine conforms to the Engine seam" + "SenseVoiceEngine conforms to the Engine seam" + "Text-only families yield a single full-text segment") RED：ChineseEnginesTests——seam spy 注入、backend id、單段全文（start 0/end=duration/confidence nil）、language hint 映射（zh→常數、de→auto）、factory throw → TranscriptionError 命名 backend、CreateOnceStore 單次。先紅
- [x] 1.2 GREEN：ParaformerEngine + SenseVoiceEngine 實作（照 ParakeetEngine 模板）。驗證：全套件綠

## 2. 接線

- [x] 2.1 (design D4; spec model-grid "Full-family catalog") BackendID ×2、ModelGrid live rows、ModelRegistry isRunnableModel/memoryEstimates、Router availableOrdered、CommandCore live()、listModels。既有測試斷言同步。驗證：全套件綠

## 3. 實測＋收尾

- [x] 3.1 (design D5) zh-TW 實測：cv-zhtw 套件兩家族 CER + RTF + 字系觀察，對照 whisper baseline；數字入 issue comment/PR；grid verified 依實測翻正。驗證：store 有 measured rows
- [x] 3.2 README（backends 段 + 中文家族說明）+ CHANGELOG。驗證：條目指向 #50
