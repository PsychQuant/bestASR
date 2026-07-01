## Context

bestASR 現況（兩輪 change 已歸檔）：Swift Apple Silicon CLI，benchmark-driven 兩層 router，WhisperKit + whisper.cpp 雙 backend，`TranscribeOptions(model, quantization, language)`，`~/.bestasr/` 家目錄慣例已由 benchmark 快取建立。無任何 context 輸入機制。

需求源：issue #3（context 校準，Clarification 已拍板 pipeline）+ issue #4（plugin marketplace）+ 2026-07-02 discuss 六項結論。使用者指示合一設計——`context.json` 是 core 與 plugin 的共同契約，單一 change + 單一 spec 消滅 schema 漂移。

資料流全景：

```
文件資料夾 ──(context-ingest skill, agent)──▶ context.json ──(core render)──▶ backend prompt
    │                                                                            │
    └— .txt/.md 詞表（no-agent fallback，core 直讀）                              ▼
                                                                        ASR ──▶ SRT
                                              最終 SRT ◀──(srt-proofread skill, agent：三軸對齊)
```

## Goals / Non-Goals

**Goals:**

- 資料夾有內容 → path 1 自動生效（prompt biasing）且 `--explain` 可解釋；資料夾空 → 行為零改變。
- `context.json` schema v1 成為 frozen contract，core 消費、兩個 plugin skill 產出/引用。
- Benchmark 能量測 ±context 的 CER/WER delta（證明 biasing 有效的量尺）。
- Repo 可被 `claude plugin marketplace add` 安裝；plugin 承載 path 2（agent 校對）與 ingestion。
- 全行為有 Swift Testing 覆蓋（engines/agent 不需真跑）。

**Non-Goals（明確排除）:**

- Core 不解析 pdf / docx / 圖片（歸 context-ingest skill 的 agent 能力）。
- 不做 diarization；speaker 軸完全依賴 context names + agent 判讀（沿襲既有 non-goal）。
- 不做 MCP server 形態的 plugin（skill-based 先行；MCP 留待實際需求）。
- 快取不存 context-biased 量測（router 推薦維持 context 中立，`BenchmarkRecord` schema 不動）。
- bestasr binary 不內建任何 LLM 呼叫（path 2 校對完全在 agent/plugin 層）。
- 不做 context 自動更新/監看（使用者或 agent 主動改檔）。

## Decisions

### D1: 資料夾三層解析 — flag > cwd > 全域

解析順序：`--context-dir <path>`（明確指定）> `./bestasr-context/`（工作目錄）> 家目錄 `.bestasr/context/`（全域），first-hit wins，不合併多層。解析結果（含「無 context」）一律進 recommendation reason。
- 理由：cwd 層讓「這個專案的錄音用這批術語」自然成立；全域層服務常用人名；不合併避免「哪個詞從哪來」不可追。
- 替代：單一全域資料夾。否決——跨領域術語互相污染。

### D2: context.json schema v1 — names 吸收 speakers

```json
{
  "version": 1,
  "language": "zh",
  "terms": ["benchmark-driven", "CoreML"],
  "names": [{ "name": "鄭澈", "aliases": ["Che"], "role": "主持人" }],
  "phrases": ["本機語音辨識模型的智慧路由器"],
  "notes": "自由文字，只給 srt-proofread agent 參考，不進 prompt"
}
```

`version` 必填（未知版本明確報錯）；`names[].aliases`、`names[].role`、`language`、`phrases`、`notes` 選填。speaker 不另立欄位——speaker 就是帶 role 的 name，一個結構同時服務 prompt biasing（name + aliases 進 prompt）與 path 2 speaker 軸（role 供 agent 對齊）。
- 替代：獨立 speakers[]。否決——ingest skill 要判斷同一人放哪邊，兩欄位 drift 風險更高。

### D3: Prompt 是自然文字，JSON 只是交換格式

Render 規則：依 **names(+aliases) → terms → phrases** 順序串成逗號分隔清單（Whisper initial prompt 的有效形態是「像前文逐字稿的自然文字」；JSON 塞進 prompt 浪費 token 且誘導輸出 JSON 樣式）。預算 ~200 tokens：WhisperKit 路徑用 pipeline tokenizer 實數計；whisper-cli 路徑用字元啟發式（CJK 字 ≈ 2 tokens、ASCII word ≈ 1.5 tokens，保守截斷）。放不下的項目整項略過（不切半個詞），略過清單記錄供 explain。
- 替代：prompt 內容用 JSON。否決（使用者 Clarification 確認 JSON 指交換檔格式）。

### D4: Core 輸入面 — context.json + 純詞表，其他冷拒

資料夾內讀取：`context.json`（canonical）+ `*.txt` / `*.md`（一行一詞併入 terms；空行與 `#` 開頭行跳過）。遇到其他副檔名（pdf/docx/pptx/圖片…）→ 不解析，列入 ignored 清單，explain 與 verbose 輸出提示「執行 context-ingest skill 轉換」。絕不靜默忽略。
- 理由：沒裝 plugin 的純 CLI 使用者仍能用 path 1；冷拒 + 大聲 = WhisperCppEngine 模型缺失指引的同款誠實。

### D5: 架構 seam — Context 模組獨占，engines 保持笨

新模組 `Sources/BestASRKit/Context/`（ContextSchema / ContextLoader / PromptRenderer）獨占：資料夾解析、schema decode 與驗證、詞表合併、prompt rendering 與預算。`TranscribeOptions` 只增 `prompt: String?`；兩個 engine 只做「把 prompt 交給 backend 機制」（WhisperKit：decode options 的 prompt tokens，經 pipeline tokenizer encode，實作時對 checkout 原始碼核對 API；whisper-cli：`--prompt` 旗標）。CommandCore 負責 wiring（resolve → load → render → options）。
- Depth check：adapter 恰一個（ContextLoader）；seam 藏真行為（解析+驗證+預算）非 pass-through；deletion test——刪 Context 模組，transcribe 退回無 biasing 仍完全可用 ✓。
- 替代：engine 直接吃 contextDir。否決——兩 engine 重複邏輯、測試面翻倍。

### D6: Benchmark ±context — 報表 delta，快取只存 baseline

`benchmark --context-dir` 時：每候選跑兩輪計時量測（baseline 無 prompt、context 有 prompt；各自沿用既有暖身規則），報表加「CER/WER(ctx)」與「Δ」欄；`--json` 同步加欄位。**快取仍只 upsert baseline record**——context 效果隨音檔與文件而變，污染快取會讓 router 推薦失去可比性；`BenchmarkRecord` schema 因此完全不動（asr-routing spec 零波及）。
- 替代：快取存 context-biased 數據 + schema 加旗標。否決——router 消費語意複雜化，v1 不值得。

### D7: Plugin 形態 — skill-based ×2，同 repo marketplace

`.claude-plugin/marketplace.json`（repo 根）+ `plugins/bestasr/`（`.claude-plugin/plugin.json` + `skills/context-ingest/SKILL.md` + `skills/srt-proofread/SKILL.md`）。ingestion 與校對本質是 LLM 工作，agent 的多模態讀檔能力就是 parser——skill 是正確形態；MCP server（Swift binary + notarization）留待未來需求。plugin.json 版本與 `BestASRVersion.current` 對齊，release 時同步 bump（common-release-flow 規約首次在本 repo 適用）。

### D8: SRT 三軸對齊契約 — spec 持有，skill 引用

Path 2 的 normative 規則寫進 `context-calibration` spec（單一 source of truth），`srt-proofread` skill 引用不複製：校對以 SRT cue 為單位；**時間碼不可變**；只改「有 context 依據」的內容（term/name 佐證）；speaker 標註使用 names[]（role 輔助判讀）；輸出＝校正後 SRT + per-cue diff 摘要（供人抽查，防 agent 幻覺改壞正確內容）。

### D9: Explain 揭露格式

`--explain`（stderr）在既有 reason/warnings 之後加 context 段：resolved 資料夾路徑、注入值總數與逐項（截斷前）、被預算截斷的項目、被忽略的檔案清單。`recommend` JSON 不加新頂層鍵（reason[] 內含 context 摘要句）——維持 #3 診斷的 lean 取向。

### D10: 測試策略

沿用 mock-engine 紀律：ContextTests（三層解析、schema 驗證、詞表合併、ignored 清單、renderer 優先序/預算/截斷——鎖 discuss worked example）；EngineTests 增「prompt 轉交」斷言（mock 檢查 options / whisper-cli arguments 組裝含 --prompt）；BenchmarkTests 增 ±context 兩輪與 delta 報表；CLITests 增 --context-dir 全鏈路（fixture 資料夾）與 explain 內容。plugin skill 為 markdown，驗證＝本機 `claude plugin marketplace add` 煙測 + skill 對假 SRT/context 走查（人工）。

## Implementation Contract

**CLI 行為：**

- `bestasr transcribe <audio> --context-dir <dir>`：dir 內 context.json/.txt/.md 被載入 → prompt 注入該次轉錄；`--explain` 印 context 段（見 D9）。無 flag 時依 D1 三層解析；全部落空 → 與現行為 bit-一致。
- `bestasr recommend <audio> [--context-dir]`：JSON 形狀不變；有 context 時 `reason[]` 含一句 context 摘要（資料夾 + 注入值數）。
- `bestasr benchmark <audio> --reference <srt> --context-dir <dir>`：每候選兩輪，表格欄位新增 `CER/WER(ctx)` 與 `Δ`；`--json` 加 `context_error_rate` / `delta` 欄位；快取只寫 baseline。無 `--context-dir` → 行為與現行完全相同。

**context.json 契約**：如 D2 JSON；`version != 1` → usage error 指出支援版本；缺 `version` 或非物件 → usage error 具名檔案；空 `terms/names/phrases` 合法（等同無該類值）。

**Prompt render（可驗證 worked example，discuss 拍板）**：names=[鄭澈/Che(主持人)]、terms=[benchmark-driven, CoreML] → prompt 恰為 `鄭澈, Che, benchmark-driven, CoreML`；預算不足時 phrases 整項先截、其次 terms 尾端，names 最後；截斷項清單非空時 explain 必列。

**三軸對齊契約（plugin 消費）**：cue 為單位；start/end 時間碼 SHALL NOT 變動；無 context 依據的內容 SHALL NOT 改寫；輸出含 per-cue diff。

**Marketplace**：`claude plugin marketplace add PsychQuant/bestASR`（或本機路徑）成功列出 bestasr plugin；`plugins/bestasr/.claude-plugin/plugin.json` 的 version 與 `BestASRVersion.current` 相等（測試斷言字串相等）。

**驗收**：`swift test` 全綠（Context/Engine/Benchmark/CLI 新斷言）；本機 smoke——(1) 建 fixture 資料夾（context.json + 一個 .txt + 一個假 .pdf）→ transcribe --explain 顯示注入與 ignored；(2) benchmark ±context 對 say 合成音檔顯示 delta 欄；(3) marketplace add 煙測通過。

**Scope 邊界**：in scope＝上述全部；out of scope＝Non-Goals 全項（尤其 core 解析富格式、diarization、MCP、快取存 ctx 數據）。

## Risks / Trade-offs

- [Prompt biasing 過強誘發幻覺（把 context 詞塞進沒說的地方）] → benchmark ±context delta 是量化防線；explain 讓人看見注入了什麼。
- [WhisperKit prompt API 細節（tokenizer encode → promptTokens 或同等機制）隨版本變動] → 實作第一步對 `.build/checkouts/WhisperKit` 現碼核對（沿 5.2 先例）；engine 介面已把差異封在 transcribeRaw 內。
- [whisper-cli `--prompt` 對 CJK 偏誤效果未實測] → smoke 階段以中文 fixture 實測一次；效果弱也不影響契約正確性（值仍如實注入）。
- [token 預算啟發式（CJK≈2/word≈1.5）與真實 BPE 有誤差] → 保守截斷 + 寬容度（預算 200 < Whisper 實限 ~224）；截斷永遠可見。
- [srt-proofread 由 agent 執行，品質不可 CI] → 契約層防護（diff 輸出 + 「無依據不改」規則）+ 人工抽查；此為 skill 形態的固有 trade-off。
- [plugin 版本同步靠紀律] → 測試斷言 plugin.json == BestASRVersion 讓漂移在 `swift test` 就爆。
