# 設計：`transcript-record`（bestasr）＋ `academic-record`（sinica-admin）

- 日期：2026-07-21
- 狀態：設計已審（brainstorming 產出）；追蹤於 PsychQuant/bestASR#108
- 作者：鄭澈 × Claude

## 動機

2026-07-20 伍麗華委員在立法院教文委員會質詢中研院（原住民精準健康），需要把該段質詢轉成逐字稿並歸檔進 `indigenous_precision_health` 專案、附回 IDD issue #1。實作過程手工做了一整條 pipeline：**選對來源 → 抓音檔 → bestASR 轉錄 → 官方 whisperx 交叉比對 → 簡轉繁校對 → 產出可讀 .md（metadata＋語者本文＋deliverable 摘要＋待核清單）→ 歸位到正確資料夾 → 附回 issue**。

現有工具鏈缺口確認：

| 階段 | 現有 skill | 缺口 |
|------|-----------|------|
| 來源 → SRT | `bestasr:transcript` | 停在 SRT |
| SRT → 修正 SRT | `bestasr:srt-proofread` | 停在 SRT |
| 逐字稿 → 正式公文會議記錄 .pdf | `sinica-admin:meeting-minutes` | 摘要體、另一海拔、吃逐字稿當輸入 |
| **SRT → 可讀 .md 記錄（語者本文＋重點＋待核）＋歸位** | ❌ 無 | 就是這次手工做的那一段 |

## 架構：兩層

```
使用者：「幫我把這場質詢做成記錄」
  │
  ▼  B: academic-record (sinica-admin)  ── 機構/學術層（薄）
  │    · 認場景（質詢/協調會/演講）
  │    · 立院→IVOD 抓源（避直播陷阱）＋官方 whisperx 第二份稿
  │    · 載 /colleague-che-cheng-academic 寫場景化重點摘要
  │    · 歸位到對的 Academic repo（依 rules）
  │    · 綁 IDD issue / 接 meeting-minutes（選配）
  │       │  invoke
  │       ▼  A: transcript-record (bestasr)  ── 通用引擎
  │            · invoke bestasr:transcript → SRT
  │            · invoke bestasr:srt-proofread
  │            · opencc 簡→繁
  │            · 交叉比對第二份稿（若有）
  │            · 產通用 .md 記錄 + 存檔
```

**composition 方向**：`academic-record` → `transcript-record` → `bestasr:transcript` / `srt-proofread`。每層只做上一層沒做的，不重寫。
- **A 可單獨用**（通用，任何人）。
- **B 一定經過 A**（B 只加機構知識）。
- Skill 之間不是函式呼叫，而是一個 skill 的 workflow 裡以 Skill 工具 invoke 另一個 skill。

## Skill A：`transcript-record`（bestasr plugin）

**定位**：通用「口語來源 → 一份乾淨、可讀、帶時間碼的 .md 逐字稿記錄」。對比既有 `transcript`（只到 SRT）。A 不含任何機構知識、不載入人格。

**description 觸發**：使用者說「把這個做成逐字稿記錄／整理成 .md 記錄」並附來源；或手上已有 SRT 想整理成可讀記錄。（要與 `transcript` 區隔：`transcript` 產 SRT，`transcript-record` 產歸位的 .md 記錄。）

**輸入**：任意來源（URL／本地音視訊／現成 SRT）。

**步驟**：

| # | 動作 | 委派 / 自做 |
|---|------|-------------|
| 0 | 無來源就主動問 | 自做 |
| 1 | 取得＋轉錄 → SRT | **invoke `bestasr:transcript`**（安全驗證、yt-dlp/ffmpeg、context biasing、單次 Bash 呼叫鐵律都在它那）。輸入已是 SRT 就跳過 |
| 2 | 校對 SRT | **invoke `bestasr:srt-proofread`**（有 context.json 時）；無 context gracefully 略過 |
| 3 | 簡→繁 | 自做（`opencc` s2twp，偵測到簡體才轉；沒裝就提示 `pip install opencc-python`，不吐簡體了事） |
| 4 | 交叉比對第二份稿（選配） | 自做（使用者給/指向同來源第二份稿時 reconcile，**保留分歧＋標待核，不硬選**） |
| 5 | 產通用 `.md` 記錄 | 自做（見下方格式） |
| 6 | 存檔 | 自做（問位置 or sensible default，如來源旁／`./transcripts/`；**不假設 repo 結構**） |

**通用 .md 記錄格式**：
- metadata 表：來源／時間／長度／語言／用的模型
- **語者本文**：SRT cue 併成可讀段落＋時間碼；語者標註「**有 diarization 或 context names 才標，否則不標**」
- **重點摘要**：通用、中性（A 不載入任何人格）
- **待核清單**：低信心專名，**永不臆造**

**輸出**：一份 `.md` 記錄（＋保留校對後 SRT 當機讀 provenance）。檔名慣例：**`<slug>_逐字稿_<date>.md`**（`<slug>` 取自來源/主題，`<date>` 為 `YYYY-MM-DD`）。

**紀律**：本文近逐字、不摘要化；時間碼沿用 SRT；raw 音檔/SRT 落 job tmp 或 gitignored，**不主動 `git add`**。

## Skill B：`academic-record`（sinica-admin plugin）

**定位**：鄭澈的中研院/學術記錄層。認得「這種東西該去哪抓、記完放哪、綁哪個 issue、要不要轉公文」。薄 —— 轉錄與 .md 產出全委派 A。

**description 觸發**：「把這場立院質詢／協調會／演講做成學術記錄並歸位」，或指向一個 IVOD／會議來源要正式記錄進 Academic repo。

**步驟**：

| # | 動作 | 說明 |
|---|------|------|
| 1 | 認場景＋抓源 | **質詢** → 立院 IVOD（g0v `ly.govapi.tw/v2/ivods?日期=YYYY-MM-DD`，**日期查再篩委員**，依委員切段 Clip，避開國會頻道直播陷阱）＋ffmpeg 抽音軌；IVOD 單筆有官方 whisperx 就抓來當第二份稿。**協調會/演講** → 依實際來源（Plaud／本地／YouTube VOD） |
| 2 | **invoke A（`transcript-record`）** | 把來源＋第二份稿丟給 A → 拿回通用 .md 記錄 |
| 3a | 場景化重點摘要 | 載 `/colleague-che-cheng-academic`：質詢→要求/deadline 表；協調會→決議/待辦 |
| 3b | 歸位 | 依 `correspondence-organization`／`research-lines` 規則**提議**位置（如 `indigenous/coordination/<date>_<event>/`），confirm 後放；被否決就改問 |
| 3c | 綁 IDD issue（選配） | 附留言／更新 checklist，**post 前先給使用者看** |
| 3d | 接 `meeting-minutes`（選配） | 協調會要正式公文時 chain 過去 |
| 4 | 隱私邊界 | 公共記錄（IVOD、公開 FB）可 commit；raw 私人會議音檔/稿 defer gitignore |

**輸出**：歸位好的 `.md` 記錄 ＋（選配）issue 連結 ＋（選配）meeting-minutes handoff。

一句話：**A 給乾淨逐字稿 .md；B 決定去哪抓、放哪、綁什麼、要不要轉公文。**

## Edge cases

| 情況 | 處理 | 歸屬 |
|------|------|------|
| 來源是國會頻道常駐直播（`is_live: true`） | 偵測到 → pivot 去 IVOD 用日期查 | B |
| IVOD 委員名含族名比對 0 筆 | 用日期查再篩委員，不用委員名硬比對 | B |
| 兩份機器稿都有錯／分歧 | reconcile 時保留分歧＋標待核，不硬選 | A |
| 低信心專名 | 待核，永不臆造 | A |
| 無 `context.json` | proofread 步驟 gracefully 略過 | A |
| `opencc` 沒裝 | fallback 提示安裝，不吐簡體 | A |
| 第二份稿抓不到 | 用單一來源產出 | A |
| Bash 執行模型（取得+轉錄同一次呼叫） | 委派 `bestasr:transcript` 自動守住 | A |
| 歸位位置被否決 | 改問，不硬放 | B |
| raw 音檔/SRT | 落 job tmp／gitignored，不主動 `git add` | A+B |

## 測試 / 驗證

Skill 是 instruction doc 不是 code，驗證＝四層：
1. **結構** → `plugin-validator` agent（frontmatter、檔案結構）。
2. **品質/觸發** → `skill-reviewer` agent（description 觸發力、best practices）。
3. **Golden example（回歸基準）** → 伍麗華 IVOD Clip 170600 完整 case（來源→IVOD→A→B→歸位 `indigenous/coordination/`→issue #1）寫進 spec/examples。
4. **Invoke 鏈** → 確認 `B → A → bestasr:transcript/srt-proofread` 串得起來。

## 明確不做（YAGNI / out-of-scope）

- A **不**做機構歸位、IDD 綁定、人格語氣 —— 那些是 B。
- B **不**重寫轉錄/校對/繁化 —— 全委派 A。
- **不**把 A/B 跟 `meeting-minutes` 合併 —— 三者不同海拔，B 需要公文時 chain 到 meeting-minutes。
- 雲端分享連結（Google Drive/Dropbox/iCloud）沿用 `bestasr:transcript` 現況（不在 MVP，先下載本地）。
- IVOD 以外的其他議會/法院影音來源，先不特別支援（B 目前只寫死立院 IVOD）。

## 待決（實作階段解）

- che-local-plugins 主 repo 位置（scaffold B 時確認；目前只在 worktree 見到）。
- 版本/發布：A 動到 bestasr plugin → 走 mcp/plugin release 流程；B 動到 che-local-plugins → 該 repo 的 plugin-update。

（已定：A 的 `.md` 記錄檔名慣例＝`<slug>_逐字稿_<date>.md`，見 Skill A「輸出」段。）

## Examples

### A+B 端到端 golden example：伍麗華 2026-07-20 立院質詢

實際執行紀錄（2026-07-21，先於 skill 存在時手工跑），驗證 `academic-record` → `transcript-record` → `bestasr:transcript`/`srt-proofread` 鏈：

1. **抓源（B）**：原給國會頻道 YouTube `Qo9QwuCpV3s` → 偵測 `is_live:true`（常駐直播端點，抓不到單場）→ pivot g0v IVOD：`日期=2026-07-20` → 篩「伍麗華Saidhai Tahovecahe」→ **Clip 170600**（10:15:40–10:25:51）。取 `video_url`(m3u8) + `transcript.whisperx`(官方稿)；`ffmpeg -vn -c:a copy` 抽 `out.m4a`（611s）。
2. **轉錄+校對（A→bestASR）**：whisper large-v3-turbo（CER 0.7%）+ indigenous `.bestasr/context` 30 專名 biasing → SRT；opencc s2twp 簡→繁；與 IVOD whisperx 交叉比對，分歧標【待核】（中醫院/中研院、國務院/國衛院、召委/趙委…）。
3. **記錄（A）**：產 metadata＋語者本文（伍麗華委員／陳建仁院長／陳君厚祕書長）＋deliverable 摘要＋待核清單的 `.md`。
4. **機構層（B）**：場景化摘要抓出**兩項要求**（精準健康書面報告 1 個月內 ≈8/20；民族所×佳平部落 2 週內 ≈8/3）；歸位 `indigenous_precision_health/coordination/2026-07-20_伍麗華立院質詢/`；綁 IDD issue #1（附全文逐字稿留言、更正 YouTube 直播來源、登記第 2 項要求）—— post 前給使用者看過。

**Dry-run findings**：

- ✅ 鏈接完整（B→A→bestASR 名字逐字對得上）、無自呼叫。
- ✅ 兩項 deliverable 的偵測正是 `academic-record` step 3a「質詢→要求/deadline 逐項不遺漏」要保證的（第 2 項差點漏、靠逐字稿才浮現）。
- ✅ **檔名 deviation 已修**：實際檔原名 `逐字稿_伍麗華質詢_2026-07-20.md` 早於慣例定案；已 `git mv` 成 `伍麗華質詢_逐字稿_2026-07-20.md`（符合 `<slug>_逐字稿_<date>`）並同步更新 issue #1 body 路徑引用。
