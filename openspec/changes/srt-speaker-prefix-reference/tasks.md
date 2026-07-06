## 0. Design traceability

- D1 — repeated-prefix heuristic，不加 CLI flag → tasks 1.1, 1.2
- D2 — 剝除落在 referenceText 萃取層，cue 結構不動 → tasks 1.1, 1.2
- D3 — 語料檔案不進 git，登記走既有 `~/.bestasr/corpora/` 慣例 → task 2.1

## 1. referenceText speaker-prefix 剝除（TDD）

- [x] 1.1 (design D1/D2; spec benchmark "Parse SRT reference into ground truth") RED：測試——重複前綴（含帶空格姓名 `Kara Swisher: `）被剝、單次 `Note: ` 保留、cue.text 原文不動、無前綴 SRT 輸出不變。先紅。驗證：目標測試紅、原因正確
- [x] 1.2 GREEN：`SRTParser.referenceText(from:)` 實作 repeated-prefix heuristic（prefix ≤40 字元、不含 colon、出現 ≥2 次者剝）。驗證：全套件綠

## 2. 語料登記＋收尾

- [x] 2.1 (design D3) 檔案搬 `~/.bestasr/corpora/jobs-gates-d5-2007.{mp3,srt}`＋`bestasr corpus add --language en` live 登記；驗證：`corpus list`（或 store 查詢）看到 row、duration≈4866s
- [x] 2.2 README corpora 段補 speaker-labeled SRT 說明＋CHANGELOG 條目。驗證：條目存在指向 #55
