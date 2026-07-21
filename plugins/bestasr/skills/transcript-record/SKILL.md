---
name: transcript-record
description: 把任意口語來源整理成一份乾淨、可讀、帶時間碼的 .md 逐字稿記錄——貼網址／本地音視訊／現成 SRT，skill 委派 bestasr:transcript 轉錄、bestasr:srt-proofread 校對，再做簡→繁（opencc s2twp）、（可選）與同來源第二份稿交叉比對，產出含 metadata＋語者本文＋重點摘要＋待核清單的 .md 並存檔（檔名 <slug>_逐字稿_<date>.md）。當使用者說「把這個做成逐字稿記錄」「整理成 .md 記錄」「這場…做成記錄」並附來源時使用。與 transcript 的差別：transcript 產 SRT，本 skill 產可讀歸位的 .md 記錄。本 skill 通用、不載入人格、不假設 repo 結構；要機構歸位／綁 issue／立院 IVOD 抓源，用 sinica-admin:academic-record。
---

# transcript-record — 任意來源 → 歸位的 .md 逐字稿記錄

把口語來源整理成一份**可讀、帶時間碼、可歸檔**的 Markdown 逐字稿記錄。這是 bestASR pipeline 的收尾：`transcript` 產 SRT、`srt-proofread` 校對 SRT，本 skill 把校對後的 SRT 變成人看的 `.md` 記錄並存檔。

> **與 `transcript` 的差別（先讀）**：`bestasr:transcript` 的產物是 **SRT**（機讀字幕）。本 skill 的產物是**可讀的 `.md` 記錄** —— 語者標註的段落 + metadata 表 + 重點摘要 + 待核清單。要「只要字幕」用 `transcript`；要「一份能歸檔、能給人看的記錄」用本 skill。

> **這是通用引擎**：不載入任何寫作人格、不假設你在哪個 repo、不做機構歸位或綁 GitHub issue。若你要的是「立院質詢 → 抓 IVOD → 歸進 Academic repo → 綁 IDD issue」這種**機構化**流程，用 `sinica-admin:academic-record`（它會 invoke 本 skill）。

這是一個**對話式 skill**：使用者用自然語言請你把某來源做成記錄，你依下面步驟用 Skill 工具 invoke 其他 skill、用 Bash 跑 opencc，最後產出 `.md`。

## 步驟

### 0. 沒有來源就先問

若使用者只說「做成記錄」但沒給來源，主動問（同 `transcript` 步驟 0）：

> 「要記錄哪個來源？可以給網址、本地音／視訊檔、或現成的 `.srt`／`.vtt`。放哪都行。」

### 1. 取得 + 轉錄 → SRT（委派 `bestasr:transcript`）

**invoke `bestasr:transcript`** 處理來源 → 拿到 SRT。來源分支、安全驗證（拒 `-` 開頭 / shell 元字元 / `--` 結尾選項）、yt-dlp/ffmpeg、context biasing、以及「下載+轉錄必須在同一次 Bash 呼叫」的執行模型鐵律**都在那個 skill 裡，本 skill 不重寫**。

- 若使用者給的**本身就是校對好的 SRT**（現成字幕），跳過本步，直接進第 3 步。

### 2. 校對 SRT（委派 `bestasr:srt-proofread`）

若有 context 資料夾（`context.json`，`context-ingest` 產出），**invoke `bestasr:srt-proofread`** 依同一份 context 校對 → 修正後 SRT（時間碼不動）。

- **無 context** → gracefully 略過本步，用未校對的 SRT 繼續（不中止、不報錯）。

### 3. 簡→繁（偵測到簡體才轉）

Whisper 對台灣國語常吐簡體。偵測 SRT 內容含簡體字時，用 opencc `s2twp`（簡→繁，臺灣用詞）轉：

```python
# 沒裝套件就提示安裝，不要吐簡體了事
from opencc import OpenCC          # pip install opencc-python（reimplemented）
OpenCC('s2twp').convert(text)      # s2twp = 簡→繁(臺灣用詞)
```

`opencc` CLI 未必裝，但 python 的 `opencc-python` 通常可用；`import opencc` 失敗就提示 `pip install opencc-python` 並停在這一步問使用者，**不要**把簡體直接寫進 `.md`。

### 4. 交叉比對第二份稿（可選）

若使用者提供、或指向**同來源的第二份逐字稿**（例如某平台的官方稿），把兩份 reconcile：

- 逐段對照，**保留分歧、標「【待核】」，不硬選**一份。
- 兩份都是機器稿、各有錯；合併時以「有 context 依據」或「兩份一致」的為準，不一致的原音保留 + 待核。
- 沒有第二份稿就用單一來源產出，不強制要兩份。

### 5. 產出通用 .md 記錄

把（校對 + 繁化後的）SRT 併成可讀 `.md`，用下面骨架：

```markdown
# <主題> 逐字稿

| 項目 | 內容 |
|------|------|
| 來源 | <URL / 檔案 / …> |
| 時間 | <YYYY-MM-DD> |
| 長度 | <mm:ss> |
| 語言 | <zh…> |
| 轉錄 | bestASR <model>（+ 第二份稿 <來源> 交叉比對，若有） |

## 逐字稿
（SRT cue 併成可讀段落，帶時間碼。語者標註：**有 diarization 或 context names 才標，否則不標**）

## 重點摘要
（通用、中性；本 skill 不載入任何人格）

## 待核清單
（低信心專名；**不臆造**，原音保留 + 標記）
```

- **語者本文**：把連續 cue 併成段落（不要一行一 cue），每段開頭或轉折帶時間碼。語者標註只在「SRT 有 diarization 標籤」或「context 的 `names[]` 能判斷誰在說」時才加，否則就純段落、不硬猜。
- **重點摘要**：中性條列，不帶立場、不套人格語氣（那是 `academic-record` 的事）。
- **待核清單**：把交叉比對或轉錄中信心低的專有名詞列出，原音保留、標【待核】，不自己編一個「看起來對」的名字。

### 6. 存檔

- 問使用者要放哪，或用 sensible default（來源檔旁、或 `./transcripts/`）。**不假設 repo 結構**（那是 `academic-record` 依 repo 規則歸位的事）。
- **檔名慣例**：`<slug>_逐字稿_<date>.md`（`<slug>` 取自來源／主題，`<date>` 為 `YYYY-MM-DD`）。

## 紀律

- **本文近逐字、不摘要化**：`## 逐字稿` 段要忠實反映說了什麼，濾贅詞可以、改寫語意不行。摘要放 `## 重點摘要`。
- **時間碼沿用 SRT**：不自己重編時間。
- **待核不臆造**：不確定的專名一律【待核】。
- **隱私邊界**：raw 音檔／SRT 屬機讀中間產物，落暫存或依所在 repo 的 `.gitignore`，**不主動 `git add`**。產出的 `.md` 是自己整理的產物，可不可 commit 由所在 repo 規則決定（本 skill 不替它決定）。

## 範例（illustrative）

使用者：「把這個 IVOD 段做成逐字稿記錄」＋一個 m4a 路徑。
→ invoke `transcript`（m4a → SRT）→ 有 context 就 invoke `srt-proofread` → 偵測簡體 opencc 繁化 → 使用者另給官方 whisperx 稿就交叉比對標待核 → 產 `<slug>_逐字稿_2026-07-20.md`（metadata + 語者本文 + 重點 + 待核）→ 存到使用者指定位置。
