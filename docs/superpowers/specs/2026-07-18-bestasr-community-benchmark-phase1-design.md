# bestASR 社群 Benchmark 記錄庫 — Phase 1 設計（資料地基）

- **日期**：2026-07-18
- **狀態**：設計已確認，待寫實作計畫（writing-plans）
- **範圍**：Phase 1（資料地基）；Phase 2（模型）另立設計
- **相關 issue**：[PsychQuant/bestASR#105](https://github.com/PsychQuant/bestASR/issues/105)（`--language auto` 未偵測語言）、[#106](https://github.com/PsychQuant/bestASR/issues/106)（SenseVoice 長檔失敗）

---

## 1. 動機與緣起

一次真實轉錄工作（62 分鐘中英混合錄音）暴露了 bestASR 的兩件事：

1. `recommend --language auto` 對非英文內容推薦了 English-only 的 `fluid-parakeet`（#105）。根因是 `auto` 未做音訊語言偵測、退回英文偏置排序。
2. bestASR 其實**已經有半套** measure→recommend 迴路（`benchmark` / `corpus` 指令 + `~/.bestasr/` 的 JSONL store），但它是**本機、易失、只由 explicit benchmark 餵回饋**。

同一次工作裡，`transcribe → srt-proofread（人校正）` 產出的 `(audio, 校正稿)` 對，正好就是 corpus 需要的 ground-truth。這引出一個更大的想法：**把真實使用的校正結果變成 corpus，讓社群共建一個 Apple-silicon 本地 ASR 的 benchmark，並讓聚合資料回饋去改善推薦。**

目前沒有這樣的東西：HuggingFace 的 Open ASR Leaderboard 是雲端大模型，不含 whisperkit / parakeet / sensevoice 在各代 M 晶片、各語言上的實測。這是本專案要填的缺口。

## 2. 完整願景與階段拆解

願景含三個耦合部分：

1. **回饋來源** — 真實轉錄 + 人校對變成 ground-truth。
2. **耐久/聚合** — 版本控制、跨機器聚合的記錄庫。
3. **模型** — 擬合/有先驗/語言感知的推薦器。

依依賴關係拆成兩階段（本 doc 只設計 Phase 1）：

| 階段 | 內容 | 依賴 |
|------|------|------|
| **Phase 1（本 doc）** | 資料地基：記錄庫（1+2 合併）+ `proofread→corpus` 貢獻流程 | — |
| **Phase 2（另立）** | 模型：recommend 消費社群先驗、擬合語言感知推薦器 | 依賴 Phase 1 的資料 |

**三條「改善 recommend」的路要分清**：

- **#105 修正** = 本機 `auto` 偵測語言（standalone bug fix，已診斷，走 `/idd-plan`）。不需要記錄庫。
- **Phase 1** = 社群資料的收集與 host。
- **Phase 2** = recommend 吃社群先驗（擬合模型）。

三者都讓 recommend 變好，但資料來源與時程各異，不可混為一談。

## 3. 定位：社群兩層 Benchmark

其他人也能上傳。這把設計從「私人記錄」提升為**社群可貢獻的記錄庫**，兩層：

- **正典（canonical）共享 corpus** — 公開、已授權的測試集，大家對它跑以得可比數字。
- **可擴充** — 任何人可貢獻新 corpus 把正典集餵大，並上傳量測。

**隱私自然解開**：社群化收不齊每位貢獻者錄音的當事人同意，故正典 corpus **必須是已授權/公開音訊**；私人錄音永不進公開集，但其**量測數字**仍可上傳（降級為聚合先驗、不進頭對頭排行榜）。

## 4. 架構（Approach A：HF dataset + GitHub）

兩個家，各司其職：

### 4.1 GitHub `PsychQuant/bestASR-bench`（大腦）

```
bestASR-bench/
├─ measurements/*.jsonl    ← 社群 PR 上傳的量測（append-only）
├─ corpus/manifest.jsonl   ← 指向 HF，存 audioSHA256 + language + license + duration + attribution
├─ leaderboard/            ← 由 measurements + manifest 自動生成
├─ tools/                  ← benchmark/submit/contribute 的 CI 與腳本
└─ .github/workflows/      ← 驗量測 PR / 驗 manifest PR
```

### 4.2 HuggingFace dataset `PsychQuant/bestasr-corpus`（音訊倉）

```
PsychQuant/bestasr-corpus (HF dataset)
└─ audio/ + reference/     ← 已授權、可串流、內容定址；HF 原生的授權欄位與 PR
```

### 4.3 連結與分層

- GitHub manifest 用 `audioSHA256` 指向 HF 條目——此欄位 `CorpusRow` schema **已有**，不改 schema。
- 本機 `~/.bestasr/`（machines / models / corpora / measurements JSONL）**維持原樣**，為私人層；bench repo 為公開/共享層。

### 4.4 資料流（完整迴路）

```
轉錄 → (人) srt-proofread → (audio, 校正後 reference)
   ├─ 已授權且同意 → 貢獻到 HF corpus + manifest PR（把正典集餵大）
   └─ 私人         → 只進本機 corpus（永不上傳）
對正典 corpus 跑 benchmark → measurement rows
   → PR 到 bench/measurements → CI 驗證 → merge
   → leaderboard 重新生成
   → (Phase 2) bestASR recommend 吃這些當先驗
```

## 5. 資料 schema

沿用 bestASR 既有 schema，僅一處增補。

- `MeasurementRow`（既有）：`modelId × corpusId × machineId → measuredAt, metricKind(WER/CER), errorRate, rtf, peakMemoryGB, warmupSeconds, appVersion, macosVersion, contextErrorRate, hfRevision`。量測 key = `(modelId, corpusId, machineId)`，同機型 + 同 corpus 天生可比。
- `CorpusRow`（既有）：`corpusId, name, language, audioSHA256, referenceSHA256, duration, audioPath, referencePath`。**注意既有 schema 不含 license/attribution 欄**。
- **社群貢獻需新增的欄位**（給 corpus manifest 與 `CorpusRow` 用）：
  - `referenceProvenance`（`human-proofread-from-<model>` / `manual` / `official`）——參考稿怎麼來的決定它多可信。
  - `license`（`CC0` / `CC-BY` / `CC-BY-SA` / `public-domain` / `own-consented`）——授權閘與 CI 驗這欄。
  - `attribution`（出處/來源，如 Common Voice clip id、原始連結）。
  - `contributor`（貢獻者 handle）。
  - 這些欄位是 Phase 1 的 schema delta；本機 `CorpusRow` 與 bench repo 的 `corpus/manifest.jsonl` 共用同一組定義以免漂移。
- `MachineRow` / `ModelRow`（既有，`ModelRow` 已含 `languages`）。

**參考稿可演進且不破壞歷史**：measurement 綁 `referenceSHA256`；參考稿一改就是新 SHA，舊量測自動歸屬舊參考。SHA 內容定址讓「ground-truth 逐步改善」與「量測可追溯」並存。

## 6. 貢獻流程

### 6.1 Flow 1 — 貢獻量測（低摩擦，多數人走）

```
bestasr corpus pull      # 新：從 HF 拉正典 corpus 到本機
bestasr benchmark        # 既有：本機各後端×模型 對 corpus 跑 → 附加 measurement rows
bestasr bench submit     # 新：打包本機新 measurements + provenance → 開 PR 到 bench/measurements/
                         #      CI 驗 schema + corpus SHA 已知 + 值域 → merge → leaderboard 重生
```

### 6.2 Flow 2 — 貢獻 corpus（把正典集餵大，較重，需人工審）

```
bestasr corpus add <audio> <ref> --language zh --license CC0   # 既有(本機)：算 SHA256、加 CorpusRow
bestasr corpus contribute   # 新：授權閘(§8) → 上傳 audio+ref 到 HF → manifest PR 到 bench/
```

### 6.3 proofread 水龍頭（把真實使用正式化）

```
轉錄 → srt-proofread(人校正) → (audio, 校正後 SRT)
    → bestasr corpus add            # 本機一定 OK
    → 已授權且當事人同意？
         ├─ 是 → bestasr corpus contribute   (→ HF + manifest PR)
         └─ 否 → 只留本機；僅 measurements 可上傳
```

**proofread 是「使 ASR 輸出變成 ground-truth」的品質閘，不可省**：未校正的 raw ASR 輸出含錯（實例：Whisper 把 Storyline 聽成 Sorrealized、中央研究院聽成宇宙中演員），不是 ground-truth。水龍頭一定**穿過** proofread。

## 7. `bestasr:bench-contribute` skill（上傳助手）

新 skill，跟既有 bestASR skill 家族一致，是兩條貢獻流程的人臉 UX。

**行為**：

1. **偵測可貢獻物**：掃本機 `~/.bestasr/`——(a) 未上傳的 measurements、(b) 剛校對好的 corpus 對。
2. **問要不要上傳（AskUserQuestion，永不自動）**：量測與 corpus 分開問。
3. **執行對應 flow**：量測 → `bench submit` PR；corpus → 授權閘 → `corpus contribute`。
4. **隱私閘住在這**（見 §8）。

**TaskCreate 提醒鉤子**：`srt-proofread`（或含校對的 `transcript`）跑完時，建一個 task「Offer bench contribution for `<audio>`」，讓「要不要上傳」的提供選項即使 session 往下走也不被遺忘。TaskCreate 只是**提醒 agent 去問**，不是 grant 自動上傳。

**核心原則：opt-in，永不自動上傳**。上傳是對外、難回收的動作（publish 到社群 repo / HF），corpus 上傳更牽涉隱私與授權，故一律先問。

## 8. 信任/驗證與隱私授權閘

### 8.1 量測信任模型（透明自報，不假裝驗證）

硬事實：無法重跑別人的硬體。設計不假裝驗證做不到的事，用三層透明機制：

1. **自報 + 豐富 provenance**：contributor、machine spec、appVersion、macOS 版本、時間、corpus SHA、model revision + quantization。
2. **可重現性**：provenance 足以讓同機型的人重跑確認/反駁。
3. **統計離群標記（軟性）**：CI 對每組 `(機型, model, corpus)` 算中位數；偏離過大 → 加 `⚠ outlier 待人看` 標籤，**人審、不自動拒**。

**leaderboard 誠實標示信任等級**：每數字標「self-reported · N 貢獻者 · M 台機器 · 中位數±MAD」，不寫成「已驗證的真相」。公信力來自透明，不來自假裝的權威。

### 8.2 CI 機械驗證（measurements PR，自動）

- JSONL 合 `MeasurementRow` schema；值域（errorRate∈[0,1]、rtf>0、mem>0、日期合理）。
- 引用的 corpus SHA 存在於 manifest；modelId 存在；machineId 良構。
- 去重；provenance 欄位完整。

### 8.3 隱私/授權閘（corpus 貢獻，兩道）

- **skill 端硬擋**（像 IDD 的 gh-egress wrapper）：corpus 上傳前，沒有 `--license` ∈ 允許集（CC0/CC-BY/CC-BY-SA/public-domain/own-consented）+ **明確勾選同意聲明**（我有權公開此音訊、可識別發言者已同意）→ 非零退出，擋下。
- **內容提醒**：skill 明示「此音訊將**公開**在 HF」，要貢獻者確認無 PII/私人第三方話語——這是 CLAUDE.md 隱私鐵律的機械執行點。
- **repo 端**：manifest PR 的 CI 要 license ∈ 允許集 + 有出處/attribution；corpus PR 走**人工審**（授權查核 + 參考稿品質）才 merge。

## 9. 新增指令/工具面盤點

| 面向 | 既有（沿用） | 新增（Phase 1） |
|------|-------------|----------------|
| 轉錄/校對 | `transcribe`、`srt-proofread` skill | — |
| 本機 corpus | `corpus add`、`benchmark`、`~/.bestasr/` JSONL store | `corpus pull` |
| 上傳 | — | `bench submit`、`corpus contribute` |
| UX | — | `bestasr:bench-contribute` skill（問→執行、TaskCreate 提醒）|
| repo 側 | — | CI（驗量測 PR / manifest PR）、leaderboard 生成器 |
| schema | `MeasurementRow`、`CorpusRow` | `CorpusRow` / manifest 增補 `referenceProvenance`、`license`、`attribution`、`contributor` |

## 10. 正典 corpus 種子（刻意多語）

- 每語言幾個 CC0/公有領域短片段（30s–2min）+ 已驗證參考稿，起步涵蓋 **en / zh / ja**。來源如 Mozilla Common Voice（CC0，最安全）、LibriSpeech（CC-BY，en）。
- **刻意多語是設計硬要求、非 optional**：整個系統的存在理由連到 #105 的語言盲。種子含 en+zh 即可公開示範 #105（parakeet 在 en 贏、zh 崩），並給 Phase 2 語言感知推薦器真實訊號。
- 確切片段清單留到實作定，但多語種子不可省。

## 11. Phase 1「做完」的驗收定義

1. 兩個家就位：GitHub `bestASR-bench` + HF `bestasr-corpus`。
2. 正典 corpus 已種（≥ en/zh 兩語、皆授權）+ manifest 進 bench repo。
3. 三個新指令可用：`corpus pull` / `bench submit` / `corpus contribute`（含授權閘）。
4. `bestasr:bench-contribute` skill 存在：上傳前必問 + TaskCreate 提醒鉤進 proofread/transcript。
5. CI 驗量測 PR + manifest PR（schema/值域/授權閘/離群標記）。
6. leaderboard 由 measurements + manifest 自動生成。
7. **端到端跑通一次**（維護者自己）：pull→benchmark→submit PR→merge→leaderboard 更新；且貢獻一筆授權 corpus。
8. **隱私閘示範**：試圖上傳未授權/私人音訊 → 被拒。

## 12. 明確不在 Phase 1（→ Phase 2）

- `recommend` 消費社群先驗。
- 任何擬合/語言感知的推薦模型。
- Phase 1 停在「資料被收集、host、驗證、可 pull」。驗收 #7 的端到端只驗**資料迴路**，不驗 recommend 變準——那是 Phase 2。

## 13. 開放問題（實作階段再定）

- 種子 corpus 的確切片段清單與來源。
- `bench-contribute` skill 的 GitHub/HF 認證方式（既有 `gh` + HF token？）。
- leaderboard 呈現形式（靜態 markdown / GitHub Pages / 連到既有網站）。
- repo 命名最終確認（`bestASR-bench` / `bestasr-corpus` 為提案）。
