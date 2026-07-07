---
name: transcript
description: 把任意來源轉成 SRT 逐字稿——貼 YouTube（或任何 yt-dlp 支援的影音站）網址、本地音／視訊檔路徑、或現成字幕檔，skill 抓下來並用 bestASR ASR 轉錄。沒給來源就主動問。當使用者說「幫我轉錄這個」「做逐字稿」「這個影片／音檔轉字幕」「這個 YouTube 轉逐字稿」「下載並轉錄」並附上一個來源時使用。注意：這是「下載音訊 + bestASR 自己 ASR 轉」，品質由 bestASR 模型決定；若使用者要的是「抓 YouTube 上已有的官方／自動字幕」而不是重新辨識，那是 yt-subtitle-downloader 的工作，不要用本 skill。
---

# transcript — 任意來源 → SRT

把使用者的**來源**轉成 SRT 逐字稿。核心是「自由參考任意來源」：來源可以是網址、本地檔案、或現成字幕，放在哪裡都行——你（agent）依來源類型分支處理，不侷限於某個約定資料夾。

這是一個**對話式 skill**：使用者用自然語言請你轉錄某個來源（不是打一個叫 `transcript` 的終端指令）。你依下面的規則，用 Bash 工具實際跑 yt-dlp / ffmpeg / bestasr 完成。

> **與 yt-subtitle-downloader 的定位差異（重要）**：yt-subtitle-downloader 抓的是平台**已存在**的字幕。本 skill 是**下載音訊後用 bestASR 自己 ASR 轉錄**——來源可以完全沒有字幕，品質由 bestASR 的 measured-best 模型決定，且能吃 context calibration / diarization / effort profiles。使用者若明確要「YouTube 上現成的字幕」用那個 skill；要「重新辨識出逐字稿」用本 skill。

## 統一「來源」抽象

skill 接受任意來源，依類型分支。**沒有固定的 import 資料夾**——任意位置的檔案都能參考：

| 來源類型 | 判定 | 處理 |
|---|---|---|
| **URL** | `http(s)://`（YouTube / Vimeo / Podcast / 一般影音站，yt-dlp 支援集） | `yt-dlp -x` 抽音訊 → bestASR ASR → SRT |
| **本地音訊檔** | `.wav` / `.m4a` / `.mp3` / `.caf` / `.aac` / `.flac` | 直接 `bestasr transcribe` → SRT |
| **本地視訊檔** | `.mp4` / `.mov` / `.mkv` / `.webm` / `.avi` | `ffmpeg` 抽音訊 → bestASR ASR → SRT |
| **現成字幕** | `.srt` / `.vtt` | 正規化成 SRT（不 ASR）——字幕本身就是一種來源 |
| **無來源** | 使用者沒給 | **主動問**（見步驟 0）——不要求一開始就給完整參數 |

雲端分享連結（Google Drive / Dropbox / iCloud）**不在 MVP 範圍**——遇到時請使用者先把檔案下載到本地再提供路徑。

## ⚠️ 執行模型（最關鍵，先讀）

**Bash 工具每次呼叫都是全新 shell**：shell 變數、`trap`、暫存目錄的 EXIT 清理都**不會**跨 Bash 呼叫存活（只有 cwd 會）。因此下載／抽取型來源（URL、視訊）的「取得音訊 → 轉錄 → 產出 SRT → 清暫存」**必須寫在同一次 Bash 呼叫的單一 script 內**（見步驟 2 的完整範本）。

- ❌ **絕不**把 `mktemp` + 下載放一次 Bash 呼叫、把 `bestasr transcribe` 放另一次——第一次呼叫結束時 `trap … EXIT` 會立刻刪掉剛下載的音訊，第二次呼叫裡 `$WORK`/`$AUDIO` 也已消失，變成對空路徑轉錄、輸出空 SRT。
- ✅ 一次 Bash 呼叫跑完整條 pipeline，**SRT 用顯式 `--output` 寫到暫存目錄之外**（cwd 或使用者指定路徑），最後才清暫存。

## 🔒 來源即不可信輸入（安全鐵律）

使用者貼的來源字串可能來自第三方（轉發的「YouTube 連結」等），**當成不可信輸入**：

1. **先驗證，再交給任何工具**。URL 必須是 well-formed `http(s)://`；本地路徑必須實際存在。
2. **拒絕 `-` 開頭的來源**——否則會被 yt-dlp/ffmpeg/bestasr 當成 flag（`--exec=…` 之類 = 任意命令執行）。
3. **拒絕含 shell 元字元**的來源（`` $ ` ; | & < > ( ) `` 與換行）——雙引號**不能**中和 `$(…)`／backtick／`${…}`。
4. **一律用 `--` 結束選項**，把來源當 positional 傳——且**所有選項必須在 `--` 之前**（`yt-dlp -x … -- "$SRC"`、`bestasr transcribe --format srt --output "$OUT" -- "$AUDIO"`）；`--` 之後的任何 token 都會被 ArgumentParser 當 positional（#37 的實測錯誤即三處範本把選項接在 `--` 後）。
5. 用 shell 變數承接來源並**加雙引號**，不要把原始字串直接拼進指令列。

驗證範本（交給工具前先跑）：

```bash
validate_source() {
  local src="$1"
  case "$src" in
    -*) echo "✗ 拒絕：來源不能以 '-' 開頭（會被當成 flag）" >&2; return 1 ;;
  esac
  case "$src" in
    *'$('*|*'`'*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*|*$'\n'*)
      echo "✗ 拒絕：來源含 shell 元字元" >&2; return 1 ;;
  esac
  if [[ "$src" =~ ^https?:// ]]; then return 0; fi   # URL
  if [ -e "$src" ]; then return 0; fi                # 存在的本地檔
  echo "✗ 來源既不是 http(s):// URL 也不是存在的檔案：$src" >&2; return 1
}
```

## 步驟

### 0. 沒有來源就先問

若使用者只說「轉錄」「做逐字稿」但沒給來源，**主動詢問**，不要卡住：

> 「有沒有來源要轉錄？可以給我：
> - 網址（YouTube 或其他影音站）
> - 本地檔案路徑（音訊、視訊，或現成的 .srt/.vtt 字幕）
> 放在哪都行，貼路徑或網址給我即可。」

使用者可一次給多個來源；逐一處理。

### 1. 前置工具檢查（依來源類型，缺失即中止）

| 來源類型 | 需要 | 說明 |
|---|---|---|
| URL | `yt-dlp` **和** `ffmpeg` | `yt-dlp -x --audio-format` 靠 ffmpeg 的 postprocessor 抽音訊——**兩者都要** |
| 本地視訊 | `ffmpeg` | 抽音軌 |
| 本地音訊 | （無） | bestASR 用 AVAudioFile 直接讀 |
| 現成 `.srt` | （無） | 已是目標格式 |
| 現成 `.vtt` | `ffmpeg` | VTT → SRT 轉換 |

缺失時**中止並指引**（`brew install yt-dlp ffmpeg`），不要 fall through 去跑一定會失敗的指令。

### 2. 取得音訊並轉錄

依來源類型選對應範本。**下載／抽取型來源整條 pipeline 在同一次 Bash 呼叫內跑完**。

**URL 來源**（單一 Bash 呼叫，含前置檢查、驗證、下載、轉錄、清理）：

```bash
SRC="<url>"                    # 使用者提供的來源
OUT="./$(基於標題或使用者指定).srt"   # ⚠️ 輸出寫到 cwd（$WORK 之外），不要留在暫存目錄
validate_source "$SRC" || exit 1
command -v yt-dlp >/dev/null && command -v ffmpeg >/dev/null || {
  echo "URL 來源需要 yt-dlp + ffmpeg：brew install yt-dlp ffmpeg" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/transcript.XXXXXX")
trap 'rm -rf "$WORK"' EXIT     # 同一 shell 內有效：轉錄完成後才隨 shell 退出清掉
# 只抽音訊（-x），不下載整支影片；WAV/PCM 保真給 ASR（不用有損 aac）
yt-dlp -x --audio-format wav --audio-quality 0 \
  -o "$WORK/source.%(ext)s" -- "$SRC" || { echo "✗ yt-dlp 下載失敗（私人／地區限制／404？）" >&2; exit 1; }
AUDIO=$(ls "$WORK"/source.* 2>/dev/null | head -1)   # 不硬編副檔名——實際抽出什麼就用什麼
[ -n "$AUDIO" ] && [ -f "$AUDIO" ] || { echo "✗ 抽音訊後找不到檔案" >&2; exit 1; }
bestasr transcribe --format srt --output "$OUT" --explain -- "$AUDIO" \
  || { echo "✗ 轉錄失敗" >&2; exit 1; }
echo "✓ 完成：$OUT"
```

**本地視訊檔**（同樣單一 Bash 呼叫；WAV 保真）：

```bash
SRC="<video-path>"
OUT="./$(來源檔名).srt"
validate_source "$SRC" || exit 1
command -v ffmpeg >/dev/null || { echo "視訊抽音訊需要 ffmpeg：brew install ffmpeg" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/transcript.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
# 抽 PCM WAV（無損，ASR 保真）；bestASR 用 AVAudioFile 讀音訊、不吃視訊容器
ffmpeg -nostdin -i "$SRC" -vn -acodec pcm_s16le -ar 16000 -y "$WORK/source.wav" \
  || { echo "✗ ffmpeg 抽音訊失敗" >&2; exit 1; }
bestasr transcribe --format srt --output "$OUT" --explain -- "$WORK/source.wav" \
  || { echo "✗ 轉錄失敗" >&2; exit 1; }
echo "✓ 完成：$OUT"
```

**本地音訊檔**（不需暫存、不複製，直接讀原路徑）：

```bash
SRC="<audio-path>"
validate_source "$SRC" || exit 1
bestasr transcribe --format srt --output "./$(來源檔名).srt" --explain -- "$SRC"
```

**承接 bestASR 全部能力**（依使用者需要，加在 `bestasr transcribe` 上）：
- `--profile low|medium|high|xhigh|max`：effort 檔位（預設 `auto` 依機器狀態選；`max` = 不計時間最準）
- `--context-dir <dir>`：領域術語／人名 prompt biasing（先跑 context-ingest 產 context.json）
- `--diarize`：多說話人標 `Speaker N:` 前綴（voices/ 有 enrollment 則標 `Name:` 真名）
- `--language <code>`：指定語言（省略則自動偵測）

### 3. 字幕來源正規化（現成字幕，不 ASR）

現成字幕本身就是「來源」——直接產出目標 SRT，不重跑 ASR：

- **`.srt`** — 已是目標格式。使用者只要 SRT 就確認／複製；要清理或轉格式再處理。**不需外部工具**。
- **`.vtt`** — WebVTT → SRT，**需 ffmpeg**：`ffmpeg -nostdin -i -- "<sub>.vtt" "<out>.srt"`（去 `WEBVTT` 標頭、cue setting，時間碼 `.`→`,`，重編序號）。

正規化不改動時間碼內容（時間軸忠實保留，同 srt-proofread 鐵律）。

### 4. 交付與回報

- 輸出 SRT 路徑（在 cwd 或使用者指定，**不在暫存目錄**）
- 音訊來源：回報用了哪個 backend/model（`--explain` 輸出）
- 多來源：逐一列出每個來源 → 輸出檔

## 銜接其他 bestASR skill

- 轉錄前想校正領域術語／人名 → 先跑 **context-ingest**（文件 → context.json），再轉錄時 `--context-dir`
- 轉錄後想三軸校對（講者／時間／內容） → 跑 **srt-proofread**

## 鐵律

- **整條 pipeline 一次跑完**。下載／抽取型來源的 mktemp → 取得音訊 → 轉錄 → 輸出，寫在**同一次 Bash 呼叫**；跨呼叫會被 trap 清掉音訊、變數也不存活（見執行模型）。
- **輸出 SRT 寫在暫存目錄之外**。用顯式 `--output ./…`（cwd 或使用者指定），否則 `bestasr` 的衍生預設會把 SRT 寫在音檔同目錄（= 暫存目錄），隨 trap 一起被刪，使用者拿到「成功」卻找不到檔。
- **來源當不可信輸入**。先 `validate_source`（拒 `-` 開頭、拒 shell 元字元、確認 URL 或存在的檔），一律 `--` 結束選項、變數加引號——這是防命令／參數注入的硬性要求。
- **暫存音訊必清**。`mktemp -d` + `trap 'rm -rf "$WORK"' EXIT`（同一 shell 內）；本地音訊檔**不複製**，直接讀原路徑。
- **只抽音訊、WAV 保真**。URL/視訊一律只抽音訊（`-x` / `-vn`）、用 WAV/PCM（不用有損 aac，保 ASR 保真）；省頻寬、省磁碟。
- **失敗不假裝成功**。yt-dlp/ffmpeg/bestasr 任一步失敗都回報實際錯誤 + 非零退出，絕不輸出空 SRT。
- **字幕來源不重跑 ASR**。現成 `.srt`/`.vtt` 是來源、不是待轉錄音訊；正規化即可，時間碼忠實保留。
- **不抓平台現成字幕當「自己的 ASR 結果」**。要抓 YouTube 現成 CC 是 yt-subtitle-downloader 的工作。

## 使用者怎麼觸發（對話式）

使用者用自然語言請你轉錄，並附一個來源。例如：

> 「幫我把 https://www.youtube.com/watch?v=xxxx 轉成逐字稿」
> → 你依 URL 範本：驗證 → yt-dlp 抽音訊 → `bestasr transcribe --format srt` → 交付

> 「這個影片幫我做字幕，要最準：~/Movies/lecture.mp4」
> → 視訊範本 + `--profile max`

> 「~/rec/meeting.m4a 轉一下，多個人講話，用我的術語表 ./bestasr-context」
> → 本地音訊 + `--diarize --context-dir ./bestasr-context`

> 「~/Downloads/captions.vtt 幫我轉成 srt」
> → 字幕正規化（ffmpeg VTT→SRT），不 ASR

> 「幫我做個逐字稿」（沒給來源）
> → 先問有沒有來源、在哪
