# transcript-record + academic-record Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Tracked in:** PsychQuant/bestASR#108

**Goal:** 交付兩個 compose 的 skill —— `transcript-record`（bestasr，通用逐字稿記錄引擎）與 `academic-record`（sinica-admin，引用前者的學術記錄層）—— 把口語來源變成一份歸位的 .md 逐字稿記錄。

**Architecture:** 兩層。`academic-record` invoke `transcript-record` invoke `bestasr:transcript`/`srt-proofread`。A 通用（不載人格、不假設 repo）；B 疊上 IVOD 來源知識、repo 歸位、IDD 綁定、meeting-minutes chain。

**Tech Stack:** Claude Code skills（`SKILL.md` markdown + YAML frontmatter）。compose `bestasr:transcript`、`bestasr:srt-proofread`。引用工具：yt-dlp/ffmpeg（經 A→transcript）、`opencc`（opencc-python，s2twp）、g0v `ly.govapi.tw` API、`gh` CLI、`/colleague-che-cheng-academic`。驗證：`plugin-validator` + `skill-reviewer` agent。

## Global Constraints

- Deliverable 是 instruction 文件（SKILL.md），**不是 code**：每個 task 的 gate ＝ `plugin-validator`（結構）＋ `skill-reviewer`（觸發力/品質）＋ 伍麗華 golden example dry-run；**無 pytest / red-green**。
- 全中文內容用**繁中**；「臺」不是「台」；不用破折號「——」當 AI 式連接。
- **A 通用**：不載入任何人格、不假設 repo 結構、不做 IDD 綁定。
- **B**：載入 `/colleague-che-cheng-academic` 寫重點摘要；擁有 IVOD 來源知識／歸位／IDD／meeting-minutes chain。
- **composition 方向固定**：`academic-record` → `transcript-record` → `bestasr:transcript`/`srt-proofread`；**不重寫**轉錄/校對/繁化。
- 檔名慣例：**`<slug>_逐字稿_<date>.md`**（date＝`YYYY-MM-DD`）。
- 隱私：raw 音檔/SRT **不主動 `git add`**；公共記錄（IVOD、公開 FB）可 commit。
- skill 互相叫用是「一個 skill 的 workflow 內以 Skill 工具 invoke 另一個」，不是函式呼叫。

## File Structure

- Create：`/Users/che/Developer/bestASR/plugins/bestasr/skills/transcript-record/SKILL.md`（Skill A）
- Create：`/Users/che/Developer/che-claude-config/che-local-plugins/plugins/sinica-admin/skills/academic-record/SKILL.md`（Skill B）
- Reference（不改，當 pattern）：`plugins/bestasr/skills/transcript/SKILL.md`、`.../srt-proofread/SKILL.md`、`.../sinica-admin/skills/meeting-minutes/SKILL.md`
- Reference（設計來源）：`docs/superpowers/specs/2026-07-21-transcript-record-and-academic-record-design.md`
- Modify（發布時）：兩個 plugin 的版本 metadata（Task 4）

---

## Task 1: Author Skill A — `transcript-record`（bestasr）

**Files:**
- Create: `/Users/che/Developer/bestASR/plugins/bestasr/skills/transcript-record/SKILL.md`
- Reference: 同 plugin 的 `transcript/SKILL.md`（來源分支、單次 Bash 鐵律、安全驗證的 pattern）、`srt-proofread/SKILL.md`

**Interfaces:**
- Produces: skill `transcript-record`，可被 `bestasr:transcript-record` 叫用（Task 2 的 B 會 invoke 它）。核心產物＝一份 `.md` 記錄，檔名 `<slug>_逐字稿_<date>.md`。
- Consumes: invoke `bestasr:transcript`（來源→SRT）、`bestasr:srt-proofread`（SRT→修正 SRT）。

- [ ] **Step 1: 建目錄 + 寫 frontmatter**

建 `plugins/bestasr/skills/transcript-record/SKILL.md`，frontmatter 用以下**逐字** name/description：

```yaml
---
name: transcript-record
description: 把任意口語來源整理成一份乾淨、可讀、帶時間碼的 .md 逐字稿記錄——貼網址／本地音視訊／現成 SRT，skill 委派 bestasr:transcript 轉錄、bestasr:srt-proofread 校對，再做簡→繁（opencc s2twp）、（可選）與同來源第二份稿交叉比對，產出含 metadata＋語者本文＋重點摘要＋待核清單的 .md 並存檔（檔名 <slug>_逐字稿_<date>.md）。當使用者說「把這個做成逐字稿記錄」「整理成 .md 記錄」「這場…做成記錄」並附來源時使用。與 transcript 的差別：transcript 產 SRT，本 skill 產可讀歸位的 .md 記錄。本 skill 通用、不載入人格、不假設 repo 結構；要機構歸位／綁 issue／立院 IVOD 抓源，用 sinica-admin:academic-record。
---
```

- [ ] **Step 2: 寫 body**

實作 spec「Skill A」段。body 需含這些小節（依序）：

1. **定位 + 與 `transcript` 區隔**：一句話講「本 skill 產可讀歸位 .md，不是 SRT」，並指「要機構事找 academic-record」。
2. **步驟 0–6**（照 spec 表）：
   - 0 無來源就問。
   - 1 取得+轉錄：**invoke `bestasr:transcript`**（安全驗證/yt-dlp/ffmpeg/單次 Bash 鐵律都在它那，本 skill 不重寫）；輸入已是 SRT 就跳過。
   - 2 校對：**invoke `bestasr:srt-proofread`**（有 context.json 時）；無 context gracefully 略過。
   - 3 簡→繁（見下方 snippet）。
   - 4 交叉比對第二份稿（選配）：使用者給/指向同來源第二份稿時 reconcile，**保留分歧＋標待核，不硬選**。
   - 5 產 .md（見下方 skeleton）。
   - 6 存檔：問位置 or sensible default（來源旁／`./transcripts/`），**不假設 repo 結構**；檔名 `<slug>_逐字稿_<date>.md`。
3. **通用 .md skeleton**（body 內要放這個模板）：

```markdown
# <主題> 逐字稿

| 項目 | 內容 |
|------|------|
| 來源 | <URL / 檔案 / IVOD…> |
| 時間 | <YYYY-MM-DD> |
| 長度 | <mm:ss> |
| 語言 | <zh…> |
| 轉錄 | bestASR <model>（+ 第二份稿 <來源> 交叉比對，若有） |

## 逐字稿
（SRT cue 併成可讀段落＋時間碼；語者標註「有 diarization 或 context names 才標，否則不標」）

## 重點摘要
（通用、中性；A 不載入人格）

## 待核清單
（低信心專名；不臆造）
```

4. **簡→繁 snippet**（body 內明列，含 fallback）：

```python
# 偵測到簡體才轉；沒裝套件就提示，不吐簡體了事
from opencc import OpenCC          # pip install opencc-python（reimplemented）
OpenCC('s2twp').convert(text)      # s2twp = 簡→繁(臺灣用詞)
```

5. **紀律**：本文近逐字、不摘要化；時間碼沿用 SRT；待核不臆造；raw 音檔/SRT 不主動 `git add`。

- [ ] **Step 3: 結構驗證**

Run: dispatch `plugin-dev:plugin-validator` agent on the bestasr plugin（`/Users/che/Developer/bestASR/plugins/bestasr`）。
Expected: PASS —— frontmatter 合法、skills/ 結構正確、無缺欄。

- [ ] **Step 4: 品質/觸發驗證**

Run: dispatch `plugin-dev:skill-reviewer` agent on `transcript-record`。
Expected: 回饋。**必修**：description 觸發詞不得與既有 `transcript`（產 SRT）撞車 —— 確認「做成記錄/.md 記錄」對到本 skill、「轉字幕/轉錄」對到 `transcript`。依回饋修 body/description。

- [ ] **Step 5: Commit**

```bash
cd /Users/che/Developer/bestASR
git add plugins/bestasr/skills/transcript-record/SKILL.md
git commit -m "feat(skill): transcript-record — 通用來源→歸位 .md 逐字稿記錄（compose transcript/srt-proofread）"
```

---

## Task 2: Author Skill B — `academic-record`（sinica-admin）

**Files:**
- Create: `/Users/che/Developer/che-claude-config/che-local-plugins/plugins/sinica-admin/skills/academic-record/SKILL.md`
- Reference: sibling `meeting-minutes/SKILL.md`（voice/隱私邊界/內容紀律 pattern）；memory `legislative-ivod-transcript-source.md`（IVOD 抓法）

**Interfaces:**
- Consumes: invoke `bestasr:transcript-record`（Task 1）。用 g0v `ly.govapi.tw`、`ffmpeg`、`gh` CLI、`/colleague-che-cheng-academic`、既有 rules（`correspondence-organization`/`research-lines`）。
- Produces: skill `academic-record`，可被 `sinica-admin:academic-record` 叫用。

- [ ] **Step 1: 確認 repo + 建目錄 + 寫 frontmatter**

確認 che-local-plugins 主 repo：`/Users/che/Developer/che-claude-config/che-local-plugins`（main）。若 che-local-plugins 是 submodule，commit 要在該子 repo 內做（Step 5 處理）。
建 `plugins/sinica-admin/skills/academic-record/SKILL.md`，frontmatter 用以下**逐字**：

```yaml
---
name: academic-record
description: 把立院質詢／跨機構協調會／演講整理成正式的學術逐字稿記錄並歸檔進 Academic repo。認場景後抓對來源（立院質詢→立法院 IVOD 依委員切段、避開國會頻道常駐直播端點；協調會/演講→Plaud/本地/YouTube VOD），委派 bestasr:transcript-record 產出逐字稿 .md，再疊機構層：載入 /colleague-che-cheng-academic 寫場景化重點摘要（質詢→要求與 deadline、協調會→決議與待辦）、依 correspondence-organization/research-lines 規則提議歸位、可選綁 IDD issue（post 前先給使用者看）、協調會要正式公文時 chain 到 sinica-admin:meeting-minutes。當使用者說「把這場質詢/協調會/演講做成記錄並歸檔」「把這段 IVOD 做成學術記錄」「立委質詢轉逐字稿歸檔」時使用。
---
```

- [ ] **Step 2: 寫 body**

實作 spec「Skill B」段，body 小節：

1. **定位**：機構/學術記錄層；轉錄與 .md 全委派 A。
2. **步驟 1 認場景+抓源**。質詢分支要放**逐字**的 IVOD 抓法：

```bash
# 立院質詢：g0v IVOD，日期查再篩委員（委員名含族名，勿用委員名硬比對）
curl -s "https://ly.govapi.tw/v2/ivods?%E6%97%A5%E6%9C%9F=YYYY-MM-DD&limit=100"   # 日期=YYYY-MM-DD
#   → 篩 委員名稱 含目標委員、影片種類=Clip（依委員切好段）
#   → 單筆 https://ly.govapi.tw/v2/ivods/<IVOD_ID> 取 video_url(m3u8) 與 transcript.whisperx(官方第二份稿)
ffmpeg -y -i "<m3u8>" -vn -c:a copy out.m4a                                      # 抽音軌
# 陷阱：國會頻道 YouTube（is_live:true、upload_date 2022、標題滾動）是常駐直播端點，
#       抓不到單場 → 一律改走 IVOD。
```

3. **步驟 2**：invoke `bestasr:transcript-record`，把 `out.m4a` ＋ IVOD `whisperx`（第二份稿）交給它 → 拿回通用 .md。
4. **步驟 3a–3d**：載 `/colleague-che-cheng-academic` 寫場景化摘要（質詢→要求/deadline 表；協調會→決議/待辦）；依 rules **提議**歸位（如 `indigenous/coordination/<date>_<event>/`）confirm 後放、被否決改問；綁 IDD issue（附留言/更新 checklist，**post 前先給看**）；協調會要公文時 chain `sinica-admin:meeting-minutes`。
5. **步驟 4 隱私邊界**：公共記錄（IVOD、公開 FB）可 commit；raw 私人會議音檔/稿 defer gitignore。
6. **內容紀律**（沿用 meeting-minutes）：忠實不虛構、對照名單修正人名、待核不臆造、不用破折號。

- [ ] **Step 3: 結構驗證**

Run: dispatch `plugin-dev:plugin-validator` agent on `.../plugins/sinica-admin`。
Expected: PASS。

- [ ] **Step 4: 品質/觸發驗證**

Run: dispatch `plugin-dev:skill-reviewer` agent on `academic-record`。
Expected: 回饋。**必修**：description 不得與 `meeting-minutes`（產公文摘要）撞車 —— 「做成記錄並歸檔/質詢轉逐字稿」對到本 skill、「寫會議記錄/會議紀錄/正式公文」對到 meeting-minutes。依回饋修。

- [ ] **Step 5: Commit**

```bash
cd /Users/che/Developer/che-claude-config/che-local-plugins   # 若為 submodule，這裡就是子 repo 根
git add plugins/sinica-admin/skills/academic-record/SKILL.md
git commit -m "feat(skill): academic-record — 學術逐字稿記錄層（IVOD 抓源+歸位+IDD，invoke transcript-record）"
```

---

## Task 3: Invoke-chain + golden-example 驗證

**Files:**
- Modify: spec 檔加「Examples」小節（`docs/superpowers/specs/2026-07-21-...design.md`）

**Interfaces:**
- Consumes: Task 1、Task 2 的兩個 SKILL.md。

- [ ] **Step 1: 驗 invoke 鏈的名字對得上**

Run:
```bash
grep -n "bestasr:transcript-record" /Users/che/Developer/che-claude-config/che-local-plugins/plugins/sinica-admin/skills/academic-record/SKILL.md
grep -nE "bestasr:transcript\b|bestasr:srt-proofread" /Users/che/Developer/bestASR/plugins/bestasr/skills/transcript-record/SKILL.md
```
Expected: B 明確引用 `bestasr:transcript-record`；A 明確引用 `bestasr:transcript` 與 `bestasr:srt-proofread`（名字逐字對，錯一個字鏈就斷）。

- [ ] **Step 2: 伍麗華 golden dry-run（checklist，不重跑轉錄）**

對照今天已完成的產物，逐條核對「照 B 的 body 走能否重現」：
- IVOD 日期查 → 篩伍麗華 Clip 170600 → m3u8 抽音軌 ✅ 對應 Step 2 snippet
- invoke A → 簡繁+whisperx 交叉比對 → .md（metadata/語者本文/deliverable/待核）✅
- 歸位 `indigenous/coordination/2026-07-20_伍麗華立院質詢/`＋檔名慣例 ✅
- 綁 issue #1（post 前給看）✅
記下任何 body 沒涵蓋到的缺口，補回對應 SKILL.md。

- [ ] **Step 3: 寫 Examples 小節**

在 spec 檔末加「## Examples」：把伍麗華 case 當 A+B 端到端 golden example（來源→IVOD Clip 170600→A→B→`indigenous/coordination/`→issue #1）逐步列出。

- [ ] **Step 4: Commit**

```bash
cd /Users/che/Developer/bestASR
git add docs/superpowers/specs/2026-07-21-transcript-record-and-academic-record-design.md
git commit -m "docs(spec): 加 A+B 端到端 golden example（伍麗華 IVOD 170600）"
```

---

## Task 4: Release / marketplace 同步（兩個 plugin）

**Files:** 兩個 plugin 的版本 metadata（`plugin.json` / marketplace 條目）

- [ ] **Step 1: bestasr plugin 發布**

新增 skill＝plugin shell 變更。依 `common-release-flow`/`common-plugins`：bump `plugins/bestasr` 版本 → `/plugin-tools:plugin-update bestasr`（sync marketplace）。
Expected: marketplace 版本更新、push。

- [ ] **Step 2: sinica-admin 發布**

bump sinica-admin 版本 → `/plugin-tools:plugin-update sinica-admin`（che-local-plugins marketplace）。
Expected: 同上。

- [ ] **Step 3: reload + 確認 skill 上架**

Run: `/reload-plugins`，確認 skill 清單出現 `bestasr:transcript-record` 與 `sinica-admin:academic-record`。
Expected: 兩者可見、可 invoke。

- [ ] **Step 4: Commit metadata bumps**（若 plugin-update 沒自動 commit）

依各 repo 慣例 commit 版本 metadata。

---

## Self-Review

- **Spec coverage**：spec §Skill A → Task 1；§Skill B → Task 2；§Edge cases → 融入 A/B body（Step 2）；§測試 → Task 1/2 Step 3-4 + Task 3；§架構 invoke 鏈 → Task 3 Step 1；§YAGNI → 反映在「A 不碰機構事、B 不重寫轉錄」的 Global Constraints。✅ 無漏。
- **Placeholder scan**：無 TBD/TODO；frontmatter 逐字給、關鍵 snippet（opencc/IVOD curl/ffmpeg/.md skeleton）逐字給。body 細節指向 spec 對應段（spec 已完整），非佔位。
- **Type/名稱一致**：invoke 目標名 `bestasr:transcript`、`bestasr:srt-proofread`、`bestasr:transcript-record`、`sinica-admin:meeting-minutes` 全文一致；檔名慣例 `<slug>_逐字稿_<date>.md` 一致。✅
