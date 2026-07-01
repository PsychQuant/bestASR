---
name: srt-proofread
description: 依 context 文件校對 bestASR（或任何 ASR）產出的 SRT 逐字稿——三軸對齊（講話的人/時間點/內容）、時間碼絕不改動、有 context 依據才改字、輸出校正後 SRT + per-cue diff。當使用者提到「校對 SRT」「校對逐字稿」「proofread transcript」「用 context 修正字幕」時使用。
---

# srt-proofread — 三軸對齊的 SRT 校對

依 bestASR 的 **context-calibration spec 三軸對齊契約**（`openspec/specs/context-calibration/spec.md` 的「SRT three-axis alignment contract for post-ASR correction」——本 skill 引用該 normative 規則，不另立版本）校對 SRT。三軸＝**講話的人（speaker）、時間點（timestamp）、內容（text）**。

## 輸入

1. 待校對的 `.srt`（bestasr transcribe --format srt 的輸出，或任何 SRT）
2. context 資料夾（同 core 三層解析）：讀 `context.json`（terms / names+aliases+role / phrases / **notes**——notes 是給你的補充脈絡）與 `.txt`/`.md` 詞表

## 鐵律（違反任一 = 校對無效）

1. **以 cue 為單位**逐條處理；不合併、不拆分、不重排 cue。
2. **時間碼不可變**：每條 cue 的 `start --> end` 必須與輸入**逐字元相同**。
3. **有據才改**：只修「能指到 context 證據（某個 term / name / alias / phrase）」的內容——同音錯字、專有名詞誤拼、人名誤聽。找不到依據的內容**一律不動**（就算你覺得它怪）。
4. **Speaker 軸**：說話者標註/校正只用 `names[]`（role 輔助判讀誰在說話）；不虛構 context 沒有的人。
5. **輸出雙件**：校正後 SRT + **per-cue diff 摘要**（只列有改動的 cue）。

## Diff 格式（每條有改動的 cue）

```
cue 14  00:03:21,400 --> 00:03:24,100
  - 正撤說可以開始
  + 鄭澈說可以開始
  evidence: names[0] 鄭澈（alias: Che）
```

## 步驟

1. 讀 SRT 與 context（含 notes）。
2. 逐 cue 掃描：對照 terms/names/phrases 找同音、近音、拼寫錯誤；比對 role 判斷 speaker 標註是否需補正。
3. 產出校正後 SRT（時間碼原封不動）與 diff 摘要。
4. **自驗**：cue 數量不變、每條時間碼與輸入逐字元相同、每個 diff 都有 evidence 欄。
5. 回報：改動 cue 數 / 總 cue 數、主要修正類型；提醒使用者抽查 diff（防過度校正）。

## 範例（spec SBE）

輸入 cue：`00:00:01,000 --> 00:00:02,500 / 正撤說可以開始`，context names 含 `鄭澈`（alias Che）
輸出 cue：`00:00:01,000 --> 00:00:02,500 / 鄭澈說可以開始`，diff 記 `正撤 → 鄭澈`。
