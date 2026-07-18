---
name: bench-contribute
description: 協助使用者把本機 benchmark 量測與校對好的 corpus 上傳到社群 benchmark（bestASR-bench + HF bestasr-corpus）。當使用者提到「上傳量測」「貢獻 corpus」「bench 提交」、或 transcript/srt-proofread 完成後的 TaskCreate 提醒觸發時使用。永遠先問、絕不自動上傳。
---

# bench-contribute — 社群 benchmark 上傳助手

把本機的量測數字與（已授權的）corpus 對，經使用者確認後貢獻到：

- **量測** → GitHub [`PsychQuant/bestASR-bench`](https://github.com/PsychQuant/bestASR-bench) `measurements/` PR
- **corpus** → HF dataset `bestasr-corpus`（audio+reference）+ bench repo `corpus/manifest.jsonl` PR

## 鐵律（違反任一 = skill 無效）

1. **Opt-in，永不自動上傳**。上傳是對外、難回收的動作。每一類貢獻物都先用 `AskUserQuestion` 問過才動；使用者說不，就記錄「已提供、已婉拒」並停止。TaskCreate 提醒只是**提醒你去問**，不是自動上傳的授權。
2. **corpus 授權閘（硬擋）**：上傳 corpus 前必須同時成立——
   - license ∈ `{CC0, CC-BY, CC-BY-SA, public-domain, own-consented}`
   - 使用者明確確認：「我有權公開此音訊，可識別的發言者已同意」
   - 明示「此音訊將**公開**在 HuggingFace」，請使用者確認無 PII／私人第三方話語
   任一不成立 → 拒絕該 corpus 的上傳（量測仍可上傳）。
3. **私人 corpus 的量測可上傳、corpus 本體絕不可**。私人錄音（會議、課堂、訪談）永遠只留本機。
4. **提交前機械驗證**：manifest 過 bench repo `tools/validate_manifest.py`、量測過 `tools/validate_measurements.py`，不綠不開 PR。

## 步驟

### 1. 偵測可貢獻物

- **量測**：讀 `~/.bestasr/measurements.jsonl`，比對 bench repo `measurements/` 既有列（clone 或 `gh api`），找出未提交的新列。
- **corpus**：session 脈絡中剛完成 `srt-proofread` 的 `(audio, 校正後 SRT)` 對，或使用者指定的對。

兩類都沒有 → 回報「目前沒有可貢獻的東西」並結束。

### 2. 問（AskUserQuestion，量測與 corpus 分開問）

- 量測：「有 N 筆新量測（機型 × backend × 語言），要上傳到社群 benchmark 嗎？」附上會公開的欄位預覽（機型、OS、app 版本——不含任何音訊內容）。
- corpus：「這對 (audio, 校正稿) 要貢獻到公開正典 corpus 嗎？」→ 觸發鐵律 2 的授權閘（license 選擇 + 同意聲明逐項確認）。

### 3. 執行

- **量測**：優先用 `bestasr bench submit`（若此版 binary 已有）。沒有則手動流：依 bench repo `SUBMISSION_FORMAT.md` 打包新列成 `measurements/<UTCts>-<contributor>-<machine12>.jsonl`（每列補 `contributor`/`chip`/`unified_memory_gb`），`tools/validate_measurements.py` 綠 → fork/branch → PR。
- **corpus**：優先用 `bestasr corpus contribute`。沒有則手動流：`hf upload` audio+reference 到 `bestasr-corpus`（需 `hf auth whoami` 已登入）→ manifest 追加一列（欄位見 `SUBMISSION_FORMAT.md`，`reference_provenance` 據實填如 `human-proofread-from-whisper-large-v3`）→ `tools/validate_manifest.py` 綠 → PR。

### 4. 回報

PR URL（或婉拒記錄）、驗證輸出、上傳了什麼／刻意沒上傳什麼。

## TaskCreate 提醒鉤（被 transcript / srt-proofread 觸發）

`transcript`（產出新量測時）與 `srt-proofread`（產出校正對時）結尾會 `TaskCreate` 一個「Offer bench contribution for <audio>」task。看到該 task 時：在當下工作收尾後**回來問使用者**（步驟 2），問完（無論答案）把 task 標 completed。不要因為 session 忙就靜默略過——那正是這個 task 存在的原因。
