---
name: transcript
description: 把任意來源轉成 SRT 逐字稿——貼 YouTube（或任何 yt-dlp 支援的影音站）網址、本地音／視訊檔路徑、或現成字幕檔，skill 抓下來並用 bestASR ASR 轉錄。沒給來源就主動問。當使用者提到「轉錄」「transcript」「把這個影片／音檔轉字幕」「這個 YouTube 轉 SRT」「下載並轉錄」「幫我做逐字稿」時使用。注意：這是「下載音訊 + bestASR 自己 ASR 轉」，不是抓平台現成字幕（抓現成 YouTube 字幕請用 yt-subtitle-downloader）。
---

# transcript — 任意來源 → SRT

把使用者的**來源**轉成 SRT 逐字稿。核心是「自由參考任意來源」：來源可以是網址、本地檔案、或現成字幕，放在哪裡都行——你（agent）依來源類型分支處理，不侷限於某個約定資料夾。

> **與 yt-subtitle-downloader 的定位差異（重要）**：yt-subtitle-downloader 抓的是平台**已存在**的字幕（可能沒有、可能是機器翻譯、時間軸不定）。本 skill 是**下載音訊後用 bestASR 自己 ASR 轉錄**——來源可以完全沒有字幕，品質由 bestASR 的 measured-best 模型決定，且能吃 context calibration / diarization / effort profiles。「抓現成」vs「自己轉」是根本不同。

## 統一「來源」抽象

skill 接受任意來源，依類型分支。**沒有固定的 import 資料夾**——任意位置的檔案都能參考：

| 來源類型 | 判定 | 處理 |
|---|---|---|
| **URL** | `http(s)://`（YouTube / Vimeo / Podcast / 一般影音站，yt-dlp 支援集） | `yt-dlp -x` 抽音訊 → bestASR ASR → SRT |
| **本地音訊檔** | `.wav` / `.m4a` / `.mp3` / `.caf` / `.aac` / `.flac` | 直接 `bestasr transcribe` → SRT |
| **本地視訊檔** | `.mp4` / `.mov` / `.mkv` / `.webm` / `.avi` | `ffmpeg` 抽音訊 → bestASR ASR → SRT |
| **現成字幕** | `.srt` / `.vtt` | 正規化成 SRT（不 ASR）——字幕本身就是一種來源 |
| **無來源** | 使用者沒給 | **主動問**（見下）——不要求一開始就給完整參數 |

## 步驟

### 0. 沒有來源就先問

若使用者只說「轉錄」「做逐字稿」但沒給來源，**主動詢問**，不要卡住：

> 「有沒有來源要轉錄？可以給我：
> - 網址（YouTube 或其他影音站）
> - 本地檔案路徑（音訊、視訊，或現成的 .srt/.vtt 字幕）
> 放在哪都行，貼路徑或網址給我即可。」

使用者可一次給多個來源；逐一處理。

### 1. 前置：yt-dlp（只在來源是 URL 時需要）

URL 來源需要 yt-dlp。缺失時明確指引、不靜默失敗：

```bash
command -v yt-dlp >/dev/null || {
  echo "URL 來源需要 yt-dlp（涵蓋 YouTube / Vimeo / Podcast / 上千影音站）："
  echo "  brew install yt-dlp"
  echo "已裝好後再貼一次網址，或改提供本地檔案路徑。"
}
```

視訊本地檔的音訊抽取需要 ffmpeg（`brew install ffmpeg`）；音訊檔與現成字幕不需外部工具。

### 2. 取得音訊（依來源類型）

用專屬暫存目錄，**轉錄後一律清理**（見鐵律）：

```bash
WORK=$(mktemp -d /tmp/transcript.XXXXXX)
trap 'rm -rf "$WORK"' EXIT   # 清理鐵律：任意退出都清掉暫存音訊
```

- **URL** — 只抽音訊（`-x`），不下載整支影片（省頻寬）：
  ```bash
  yt-dlp -x --audio-format m4a --audio-quality 0 \
    -o "$WORK/source.%(ext)s" "<url>"
  AUDIO="$WORK/source.m4a"
  ```
  下載失敗（私人影片、地區限制、404）→ 回報實際錯誤，別假裝成功。

- **本地視訊檔** — ffmpeg 抽音軌（bestASR 用 AVAudioFile 讀音訊，不直接吃視訊容器）：
  ```bash
  ffmpeg -i "<video>" -vn -acodec aac -y "$WORK/source.m4a"
  AUDIO="$WORK/source.m4a"
  ```

- **本地音訊檔** — 直接用，不複製、不抽取：
  ```bash
  AUDIO="<audio-path>"   # 這種情況不需要 $WORK
  ```

- **現成字幕** — 跳到步驟 4（字幕正規化），不經 ASR。

### 3. ASR 轉錄（音訊來源）

```bash
bestasr transcribe "$AUDIO" --format srt --output "<out>.srt" --explain
```

**承接 bestASR 全部能力**（依使用者需要，可選）：
- `--profile low|medium|high|xhigh|max`：effort 檔位（預設 `auto` 依機器狀態選；`max` = 不計時間最準）
- `--context-dir <dir>`：領域術語／人名 prompt biasing（先跑 context-ingest skill 產 context.json）
- `--diarize`：多說話人時標 `[SPEAKER_N]`（voices/ 有 enrollment 則標真名）
- `--language <code>`：指定語言（省略則自動偵測）
- `--backend` / `--model`：強制特定 backend/model（預設實測最佳）

`--explain` 讓使用者看到選了哪個 backend/model 與原因（stderr）。

### 4. 字幕來源正規化（現成字幕，不 ASR）

現成字幕本身就是「來源」——直接產出目標 SRT，不重跑 ASR：

- **`.srt`** — 已是目標格式。若使用者只要 SRT，複製／確認即可；若要清理或轉其他格式再處理。
- **`.vtt`** — WebVTT → SRT：去掉 `WEBVTT` 標頭與 cue setting，時間碼 `.` 秒分隔轉 `,`（SRT 慣例），重編 cue 序號。用 ffmpeg 最穩：
  ```bash
  ffmpeg -i "<subtitle>.vtt" "<out>.srt"
  ```

正規化後不改動時間碼內容（時間軸忠實保留，同 srt-proofread 鐵律）。

### 5. 交付與回報

- 輸出 SRT 路徑（預設從來源檔名衍生，或使用者指定的 `--output`）
- 音訊來源：回報用了哪個 backend/model（`--explain` 的輸出）
- 多來源：逐一列出每個來源 → 輸出檔

## 銜接其他 bestASR skill

- 轉錄前想校正領域術語／人名 → 先跑 **context-ingest**（文件 → context.json），再 `transcript ... --context-dir`
- 轉錄後想三軸校對（講者／時間／內容） → 跑 **srt-proofread**

## 鐵律

- **暫存音訊必清**。URL/視訊來源下載或抽取的音訊放 `mktemp -d` 暫存目錄，`trap 'rm -rf "$WORK"' EXIT` 確保任意退出（成功、失敗、中斷）都清掉——下載內容不留在 `/tmp` 堆積。本地音訊檔**不複製**（直接讀原路徑），避免多餘副本。
- **只抽音訊，不下載整支影片**。URL 一律 `yt-dlp -x`；省頻寬、省磁碟，ASR 只需要音訊。
- **沒來源就問，不卡住**。空啟動時主動詢問，別要求使用者一開始給完整參數——conversational 是這個 skill 的核心 UX。
- **失敗不假裝成功**。yt-dlp 下載失敗（私人／地區限制／404）、ffmpeg 抽取失敗、bestasr 轉錄失敗——都回報實際錯誤，不靜默略過或輸出空 SRT。
- **字幕來源不重跑 ASR**。現成 `.srt`/`.vtt` 是來源、不是待轉錄音訊；正規化成 SRT 即可，時間碼忠實保留。
- **不抓平台現成字幕當「自己的 ASR 結果」**。本 skill 是 ASR 轉錄；要抓 YouTube 現成 CC 是 yt-subtitle-downloader 的工作，別混淆。

## 範例

```
# YouTube → SRT（ASR）
transcript https://www.youtube.com/watch?v=xxxx

# 本地視訊，要最準
transcript ~/Movies/lecture.mp4 --profile max

# 本地音訊 + 領域術語 biasing + 說話人辨識
transcript ~/rec/meeting.m4a --context-dir ./bestasr-context --diarize

# 現成 VTT 字幕正規化成 SRT（不 ASR）
transcript ~/Downloads/captions.vtt

# 空啟動 → skill 主動問來源
transcript
```
