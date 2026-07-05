## Context

bestASR 的 benchmark 語料現況（`scripts/fetch-corpora.sh`）：en = jfk（16 kHz）+ osr-harvard-1（10 句）；zh = FLEURS `cmn_hans_cn`（簡體，3 句串接）；ja = FLEURS `ja_jp`（3 句串接）。全部 pinned（CONVERTED 16 kHz artifact 的 SHA-256 + FLEURS revision + TSV digest）。語料經 `bestasr corpus add <wav> <srt> --language X --name Y` 註冊進 `CorpusRegistry`（content-hash keyed）。`bestasr benchmark` 對每個 corpus 算 CER（無空格語言 zh/ja/繁中）或 WER（en），measured rows append 進 `BenchmarkStore`（`~/.bestasr/store/`，本機、含 machine-specific x-realtime）。`scripts/validate-diarization.sh` 是既有的 pinned-fixture 驗證範式（REV + SHA + 具名 pick + curl + digest verify）。

此變更把「臨時、小、簡體」的語料換成「固定、對稱、繁中」的 regression 套件，並加一層 machine-independent 的退步防線。

## Goals / Non-Goals

**Goals:**

- 三語言（en / 繁體中文 / ja）各 ~20-30 句、對稱規模的固定 benchmark 語料。
- 繁體中文取代簡體——bestASR「中文」只指繁中。
- machine-independent 的 regression gate：版本間 CER/WER 不得退步，可跨機器 / CI 執行。

**Non-Goals:**

- 不 gate 速度（x-realtime，machine-dependent）。
- 不跨 model grid 跑 regression（單一固定 reference model 當 canary）。
- 不重寫 benchmark/store 核心（承接既有 CorpusRegistry / BenchmarkStore / metric）。
- 不保留簡體為可切換選項。

## Decisions

### D1 — Baseline = repo 內 pinned `benchmarks/baseline.json`，只記 CER/WER

regression gate 需要一份跨機器穩定的 golden 基準。`BenchmarkStore` 不適合：它在 `~/.bestasr/`（不進 repo）、是 append-only 本機實測、且 row 含 machine-specific x-realtime。改用進 repo、版本控制的 `benchmarks/baseline.json`。

**只記 CER/WER**：CER/WER = edit-distance(模型輸出, reference)，同 model + 同音檔 + 同 decode 參數 → 同輸出 → 同值，machine-independent。x-realtime = 時長比，machine-dependent，**不進 baseline、不進 gate**——否則不同機器跑 gate 會因速度差假退步。store 仍在本機記速度供探索，兩者分工。

### D2 — Gate model = 單一固定 reference WhisperKit model

regression gate 的目的是抓「pipeline / 模型整合退步」的 canary，一個穩定 reference model 足夠。跨 model grid 是「找本機最佳」的 explore 用途，且 grid 會變動（加 model 就要更新 baseline，gate 變脆）。選 **WhisperKit `large-v3-turbo`**（built-in、無需 brew、三語言都強、既有 SBE 表已用它）。三語言 × 1 model = 3 組 baseline 數字（實際為 corpus 數 × 1 model）。

### D3 — 繁中 = Common Voice zh-TW 固定具名 clip 清單 + digest + version pin

從 Common Voice zh-TW 挑固定的 ~20-30 個 clip（CC-0，台灣華語群眾錄音，有現成 ground-truth transcript）。**下載管道（2026-07-05 查證定案）**：官方管道自 2025-10 起僅 Mozilla Data Collective（登入制），HF 官方 repo `mozilla-foundation/common_voice_*` 已撤成空殼——**採 HF 鏡像 `fsicoli/common_voice_17_0`**（ungated、裸 curl @ pinned revision 實測 HTTP 200；佈局 `audio/zh-TW/dev/*.tar` shards + `transcript/zh-TW/dev.tsv` + `clip_durations.tsv`，與既有 FLEURS 流程機械同構）。從 **dev split** 取 clip（同 FLEURS dev-split 慣例；dev shard 約 118 MB）。

Pin 三層：HF 鏡像 **revision**（content-addressed，同 FLEURS_REV 慣例）+ **shard tar digest**（parser 碰 bytes 前驗）+ **各選中 clip 檔名與 SHA-256 digest**。**不 seed 隨機**——固定清單才可審計、可重現，符合 `fetch-corpora.sh` 既有 #15/#18 供應鏈紀律。選句時盡量涵蓋長度、數字、標點多樣性。

**Provenance caveat（誠實記載）**：fsicoli 是第三方鏡像，provenance 弱於官方；digest pinning 讓竄改可偵測（內容安全），但來源真實性依賴鏡像忠實轉載。Provenance-maximal 替代：使用者自行登入 Data Collective 下載官方 zh-TW tarball 放指定路徑、script 從該路徑同樣 digest verify 起跳（bring-your-own-tarball）——文件化為替代路徑，非預設。

**格式注意**：CV clip 是 **MP3**（tar 內）；既有 concat 用 python3 `wave` 模組（只吃 WAV），故順序必須是：shard digest verify → 抽出選中 clip → **per-clip `afconvert` 轉 16 kHz mono WAV** → python3 concat → 內嵌 verbatim SRT（cue 時間軸用 `clip_durations.tsv` + 累計 offset）。

### D4 — 每語言拆 3-5 個中長度 corpus，不全串成一個

現況把 3 句串接成單一 corpus → 單一 CER 數字。20-30 句改成每語言 **3-5 個中長度 corpus（每個 5-8 句串接）**。benchmark 對每 corpus 算一個 CER → 多個 corpus 可算 **平均 + variance**，regression gate 用平均、variance 顯示穩定性；單句/單 corpus 退步可定位。避免 20-30 個單句 corpus 造成 store row 爆量。串接沿用既有 python3 WAV concat + afconvert 16 kHz 流程。

### D5 — en/ja 同步擴充到 ~20-30，三語言對稱

現況 en（osr 10 句）、ja（FLEURS 3 句）不齊。三語言都拉到 ~20-30，regression gate 才三語言對稱可比。ja 從 FLEURS `ja_jp` dev split 多取（同既有 REV，加 clip、更新 pin）；en 從 OSR 其他 Harvard list（voiptroubleshooter Open Speech Repository 有多個 list）或 FLEURS en 補到規模。全部 pinned。

### D7 — zh 的 CER 做 script 正規化（雙側 Hant→Hans，mid-apply 裁決 2026-07-05）

實測發現（apply 階段）：Whisper 對中文**預設輸出簡體**，繁體 reference 逐字比對全算錯——cv-zhtw golden 未正規化時 CER 0.35-0.48，實際辨識內容幾乎全對（「電話→电话」逐字對應）。不處理 script，「繁中 benchmark」測到的是 script mismatch 而非辨識準確度。

**決策**：language 為 zh 時，CER 比對前把 hypothesis 與 reference **雙側**經繁→簡正規化（macOS 內建 ICU StringTransform "Hant-Hans"，零外部依賴）。方向選繁→簡因為它是 well-defined 的多對一（簡→繁有一對多歧義：发→發/髮）。**只影響 metric 內部比對**——轉錄輸出檔照模型原樣（不改使用者拿到的東西）；**ja/ko 不做 transform**（日文漢字經 Hant-Hans 會被錯誤改寫）。

誠實記載：ICU transform 表跨 macOS 版本理論上可能微變（Unicode Han 映射極穩定），tolerance 吸收；此假設列入 gate fail triage 的 provenance 面向。

### D6 — Regression gate script 沿用 validate-diarization.sh 範式

`scripts/regression-gate.sh`：確保語料已 fetch（呼叫 fetch-corpora 或假設已註冊）→ 對固定 reference model 跑 `bestasr benchmark`（或 `recommend`/`transcribe` + metric）取每 corpus 的 CER/WER → 讀 `benchmarks/baseline.json` 的 golden + tolerance → 逐 corpus 比對，超出 tolerance 即 `exit 1` 並印出退步的 corpus/語言/golden vs actual。沿用 validate-diarization.sh 的 fail-loud + pinned 紀律。

## Implementation Contract

**Behavior**：
- `scripts/fetch-corpora.sh` 執行後，註冊的語料為 en / 繁中 / ja 各 ~20-30 句（多個中長度 corpus），**無任何簡體語料**。
- `scripts/regression-gate.sh` 執行後：全部 corpus 的 CER/WER 在 baseline tolerance 內 → `exit 0` + 印通過摘要；任一 corpus 超出 → `exit 1` + 印該 corpus 的語言 / golden / actual / 差值。
- bestASR 文件（README、corpora spec）稱「中文」一律指繁體中文。

**Interface / data shape**：
- `benchmarks/baseline.json`（新 on-disk 格式，seam 在 repo 內）：物件陣列，每筆 `{ "corpus": "<name>", "language": "<en|zh|ja>", "model": "large-v3-turbo", "metric": "cer|wer", "golden": <float>, "tolerance": <float> }`。language `zh` 語意 = 繁體中文。讀者：regression-gate.sh + RegressionBaselineTests。刪掉此檔 → gate 無基準 → 失效（非 pass-through）。
- `fetch-corpora.sh` 的繁中 pin 常數（三層）：HF 鏡像 revision（`CV_ZHTW_REV`）、dev shard tar digest、選中 clip 檔名清單與各 clip SHA-256（同既有 FLEURS_* / *_SHA 常數風格）。
- corpus 註冊介面不變（`bestasr corpus add`）。

**Failure modes**：
- clip digest mismatch → fail-loud、拒絕註冊（同既有 jfk/osr digest 檢查）。
- Common Voice 下載不可用 / 版本消失 → script 明確報錯 + 指引（同 FLEURS tar 缺失處理）。
- baseline.json 缺 corpus 條目而語料有該 corpus → gate 報「baseline 缺條目」而非靜默通過。
- regression gate 只判 CER/WER 超 tolerance；速度差**不**觸發 fail。
- **gate fail 的第三種原因**：reference model 的上游 artifact（HF argmaxinc/whisperkit-coreml）更新會位移輸出——gate 失敗要對照 model provenance triage（code 退步、語料變動、還是上游模型換版），不可直接歸因 code。緩解：baseline 條目 `model` 欄記到可識別版本的粒度（模型名 + 可得時的 revision），gate 報錯訊息提示三種可能原因。

**Acceptance criteria**：
- fetch-corpora 後 `bestasr corpus list` 顯示三語言各 3-5 corpus、無簡體、繁中來源為 Common Voice zh-TW。
- regression-gate.sh 對未退步的 build `exit 0`；人為把某 baseline golden 調到不可能達成 → `exit 1` 並指出該 corpus（驗證 gate 真的會擋）。
- RegressionBaselineTests 驗 baseline.json schema 合法 + 比對邏輯（tolerance 邊界、缺條目）。
- corpora spec 的語言組成 scenario 反映繁中取代簡體 + 規模。
