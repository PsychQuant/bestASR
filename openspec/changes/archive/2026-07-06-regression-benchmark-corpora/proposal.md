## Why

bestASR 的 benchmark 語料（`scripts/fetch-corpora.sh`）有三個實質缺口：

1. **「中文」語料是簡體，不是繁體**。現有 zh 語料是 FLEURS `cmn_hans_cn`（Hans = 簡體）。專案擁有者是台灣人——bestASR 的「中文」benchmark 只指**繁體中文（台灣華語）**；簡體語料不該存在於套件。繁中 vs 簡中在 ASR 上不只字形（用詞、腔調、慣用語不同），用簡體語料測繁中，CER 不代表繁中實際表現。此變更回溯修正加簡體的方向。
2. **規模太小、統計不穩**。zh/ja 各只有 3 句（FLEURS dev split 串接成單一 corpus），單句錯就大幅影響 CER，版本間比較噪聲大。
3. **無 regression gate**。benchmark 能跑，但沒有「固定語料 + 版本間 CER/WER 不得退步」的自動防線。

核心設計張力（discuss 定案）：regression gate 要 **machine-independent** 才能跨機器/CI 當基準。CER/WER 是模型輸出對 reference 的文字比對（同模型+同音檔+同 decode → 同值），滿足；x-realtime 隨機器變，不滿足。這決定了 baseline 存哪（repo 內 pinned JSON）、gate 什麼（只 CER/WER）、model 固定與否（固定一個 reference model 當 canary）。

## What Changes

- **移除簡體 FLEURS `cmn_hans_cn` zh 語料**，改繁體中文 Common Voice zh-TW（固定具名 clip 清單 + 各 clip digest + corpus 版本號 pin，CC-0，同既有供應鏈紀律）。
- **三語言（en / 繁中 / ja）各擴充到 ~20-30 句**，對稱規模；每語言拆成 3-5 個中長度 corpus（每個 5-8 句），非全串成單一 corpus——benchmark 對每 corpus 算一 CER，多 corpus 可算平均 + variance。
- **新增 regression gate**：一份進 repo 的 pinned `benchmarks/baseline.json`（golden CER/WER + tolerance），一個 regression gate script 用固定 reference model 跑三語言語料、比對 baseline，退步即 fail。**只 gate CER/WER，不 gate 速度**。
- corpora spec 的語言組成 normative 更新（繁中取代簡體、規模）。

## Non-Goals

- **不 gate 速度（x-realtime）**：machine-dependent，跨機器會假退步。速度仍由既有 benchmark/store 在本機探索，不進 regression gate。
- **不跨 model grid 跑 regression**：gate 用單一固定 reference model 當 canary；跨 grid 是「找本機最佳」的 explore 用途，非防退步。
- **不涵蓋雲端語料來源**：只 yt-dlp 無關；語料來自 Common Voice / FLEURS / OSR 公開資料集的 pinned 下載。
- **不重寫 benchmark/store 核心**：承接既有 CorpusRegistry / BenchmarkStore / metric，只加 baseline + gate 層。
- **不保留簡體作為選項**：簡體移除是定案，非可切換設定。

## Capabilities

### New Capabilities

- `regression-benchmark`: 固定三語言語料 + repo 內 pinned golden baseline（CER/WER）+ gate script，版本間退步即 fail；machine-independent（只比文字準確度，不比速度）。

### Modified Capabilities

- `corpora`: 語言組成 normative 變更——「中文」語料為繁體中文（Common Voice zh-TW），移除簡體 FLEURS；三語言規模對稱（每語言 ~20-30 句、拆多個中長度 corpus）。
- `benchmark`: zh CER 加 script 正規化（design D7，mid-apply 裁決 2026-07-05）——中文 tag（base subtag `zh`，含 `zh-TW`/`zh-Hant`）的 CER 比對前雙側 Hant→Hans fold；ja/ko 與 `auto` 絕不 fold；交付的 transcript 不動。

## Impact

- Affected specs: `regression-benchmark`（new）, `corpora`（modified）, `benchmark`（modified — D7 zh script fold）
- Affected code:
  - New:
    - benchmarks/baseline.json（golden CER/WER + tolerance，pinned）
    - scripts/regression-gate.sh（跑固定語料、比 baseline、退步 fail）
    - Tests/BestASRKitTests/RegressionBaselineTests.swift（baseline schema + 比對邏輯的單元測試）
  - Modified:
    - scripts/fetch-corpora.sh（移簡體 FLEURS zh、加繁中 Common Voice zh-TW、擴 en/ja 到 ~20-30、拆多 corpus）
    - Sources/BestASRKit/Benchmark/{ErrorRate,TextNormalizer,BenchmarkRunner}.swift + Detect/Language.swift（D7 zh script fold：共用 base-subtag 判準、compute 傳 language）
    - openspec/specs/corpora/spec.md（語言組成 normative）
    - openspec/specs/benchmark/spec.md（D7 zh script fold normative）
    - README.md（三語言 benchmark + 繁中說明）
  - Removed:
    - （fetch-corpora.sh 內的簡體 FLEURS cmn_hans_cn 區段——非獨立檔案，隨 script 修改移除）
