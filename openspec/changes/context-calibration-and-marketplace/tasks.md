## 1. Context 模組（架構 seam）

- [x] 1.1 [P] 依 D2: context.json schema v1 — names 吸收 speakers 實作 Sources/BestASRKit/Context/ContextSchema.swift：Codable 型別 + 驗證，完成 Load and validate the context.json schema（version 必填且僅支援 1、未知版本/壞 JSON → usage error 具名檔案、notes 不進 prompt）。行為：合法 v1 載入（SBE canonical document 案例）、version 99 與非 JSON 被具名拒絕。驗證：Tests/BestASRKitTests/ContextTests.swift 鎖 SBE。
- [x] 1.2 [P] 依 D1: 資料夾三層解析 — flag > cwd > 全域 實作 ContextLoader 的解析層，完成 Resolve the context directory by three-layer precedence 與 Zero impact when context is absent 的解析面（flag 蓋 cwd 蓋全域、first-hit 不合併、全落空 → nil 且 reason 註記）。行為：三個 spec scenario。驗證：ContextTests 以暫存目錄參數化斷言。
- [x] 1.3 依 D4: Core 輸入面 — context.json + 純詞表，其他冷拒 完成資料夾讀取：Merge plain-text term lists（.txt/.md 一行一詞、跳空行與 # 行、併入 term pool 於 context.json terms 之後）與 Loudly ignore unsupported document formats（pdf/docx 等列 ignored 清單 + context-ingest 指引、絕不靜默、內容不影響 prompt）。行為：兩 spec scenario。驗證：ContextTests fixture 資料夾含 terms.txt + lecture.pdf 斷言。
- [x] 1.4 依 D3: Prompt 是自然文字，JSON 只是交換格式 實作 PromptRenderer，完成 Render context into a natural-language prompt with priority and budget：names(+aliases)→terms→phrases、~200 token 預算（WhisperKit tokenizer 實數 / CLI 路徑字元啟發式）、整項略過並記錄截斷清單。行為：worked example 輸出恰為「鄭澈, Che, benchmark-driven, CoreML」；超預算時 phrases 先截且截斷清單非空。驗證：ContextTests 鎖 SBE 與 overflow 順序。

## 2. Engine 管線

- [x] 2.1 依 D5: 架構 seam — Context 模組獨占，engines 保持笨 修改 Common engine interface：TranscribeOptions 增 optional prompt 欄位（Sources/BestASRKit/Models/DataModels.swift + Engines/Engine.swift），engines 只轉交不解析。行為：帶 prompt 的 options 傳到 backend 機制、無 prompt 時 invocation 不含 prompt 參數（兩個 MODIFIED scenario）。驗證：Tests/BestASRKitTests/EngineTests.swift mock 斷言 options 流動。
- [x] 2.2 實作兩 backend 的 prompt 落地：WhisperKitEngine 經 pipeline tokenizer encode 進 decode options 的 prompt 機制（實作前對 .build/checkouts/WhisperKit 現碼核對 API，沿 5.2 先例）；WhisperCppEngine 在 arguments 組裝加 --prompt。行為：cpp 引擎 arguments 含 --prompt 與值；wk 引擎 mock 路徑確認 prompt 進 decode options。驗證：EngineTests 對 arguments 組裝的純函式斷言 + mock。

## 3. CLI wiring

- [x] 3.1 CommandCore 接線（resolve→load→render→options）：transcribe command with options 增 --context-dir（省略時走三層解析）、recommend 的 reason[] 含 context 摘要句、確保 Zero impact when context is absent 端到端成立（無 context 時輸出與現行 bit-一致）。行為：cli spec 的 explicit context directory scenario + 空資料夾零影響。驗證：Tests/BestASRKitTests/CLITests.swift fixture 目錄全鏈路。
- [x] 3.2 依 D9: Explain 揭露格式 完成 explain mode surfaces reasoning 修改與 Explain discloses context usage：stderr 揭露 resolved 目錄、注入值、截斷項、ignored 檔案；轉錄輸出檔不受污染。行為：兩 spec scenario（含 pdf + 超額 phrase 的組合案例）。驗證：CLITests 斷言 explain 內容與輸出檔純淨。

## 4. Benchmark ±context

- [x] 4.1 依 D6: Benchmark ±context — 報表 delta，快取只存 baseline 實作 Measure the context-biasing delta 與 benchmark command 修改：--context-dir 時每候選兩輪（baseline / with-context，各自沿用暖身規則）、表格加 CER/WER(ctx) 與 Δ 欄、--json 加對應欄位、快取只 upsert baseline（BenchmarkRecord schema 不動）；無 flag 時單輪且報表形狀不變。行為：三 spec scenario + SBE delta 表。驗證：Tests/BestASRKitTests/BenchmarkTests.swift mock 兩輪與快取內容斷言。

## 5. Plugin marketplace

- [x] 5.1 [P] 依 D7: Plugin 形態 — skill-based ×2，同 repo marketplace 建 Repository installs as a Claude Code plugin marketplace（.claude-plugin/marketplace.json）與 bestasr plugin packages the agent workflows（plugins/bestasr/.claude-plugin/plugin.json + 兩個 skill 目錄骨架）。行為：本機以路徑 add marketplace 成功並列出 bestasr plugin；plugin 結構含 manifest 與兩 skill。驗證：claude plugin marketplace add 煙測（實體命令）+ 結構 ls。
- [x] 5.2 [P] 撰寫 plugins/bestasr/skills/context-ingest/SKILL.md，完成 context-ingest skill produces schema-valid context documents：指示 agent 用自身多模態能力讀任意格式 → 蒸餾 terms/names(+aliases,role)/phrases → 寫 version-1 context.json 到解析出的 context 目錄（與 D1 同三層規則）→ 完成前對照 schema 自驗。行為：skill 步驟含 schema 範例與驗證清單。驗證：內容審閱 + 對假文件夾走查一輪產出可被 ContextSchema 載入的 JSON。
- [x] 5.3 [P] 撰寫 plugins/bestasr/skills/srt-proofread/SKILL.md，完成 srt-proofread skill follows the alignment contract：引用（不複製）D8: SRT 三軸對齊契約 — spec 持有，skill 引用 之 normative 規則——即 context-calibration spec 的 SRT three-axis alignment contract for post-ASR correction（cue 為單位、時間碼不可變、有據才改、speaker 用 names、輸出校正 SRT + per-cue diff）。行為：skill 明列鐵律與 diff 輸出格式（含 evidence 欄）。驗證：內容審閱 + 假 SRT/context 走查（正撤→鄭澈 SBE 案例）。
- [x] 5.4 完成 Plugin version tracks the app version：swift test 加斷言讀 plugins/bestasr/.claude-plugin/plugin.json 的 version 字串 == BestASRVersion.current（依 D10: 測試策略 讓版本漂移在測試就爆）。行為：版本不等 → 測試紅。驗證：Tests/BestASRKitTests/CLITests.swift（或獨立 PluginTests）斷言。

## 6. 收尾

- [x] 6.1 README 更新（context workflow quick start：放文件 → 跑 context-ingest → transcribe --explain、benchmark ±context、marketplace 安裝章節）＋ 依 design Implementation Contract 驗收段本機 smoke：(1) fixture 資料夾（context.json + terms.txt + 假 pdf）→ transcribe --explain 顯示注入/截斷/ignored；(2) benchmark --context-dir 對 say 合成音檔輸出 delta 欄；(3) marketplace add 煙測。行為：契約全項成立、swift test 全綠。驗證：逐項執行並記錄輸出於 issue #3/#4 comment。
