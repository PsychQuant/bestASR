# Tasks — regression-benchmark-corpora

實作 corpora spec 的 "English standard set is scriptable and verified" + "zh/ja standard set is scriptable and verified"（MODIFIED），regression-benchmark spec 的 "Machine-independent regression baseline" + "Regression gate fails on accuracy regression"（ADDED），依 design D1-D6。

## 1. 繁中語料（Common Voice zh-TW）— design "D3 — 繁中 = Common Voice zh-TW 固定具名 clip 清單 + digest + version pin" + corpora "zh/ja standard set is scriptable and verified"
- [x] 1.1 [P] 從 fsicoli/common_voice_17_0 鏡像的 zh-TW **dev split**（transcript/zh-TW/dev.tsv + audio/zh-TW/dev shard）挑 ~20-30 個 clip（涵蓋長度/數字/標點多樣性），分成 3-5 組（每組 5-8 句）——D3 固定具名清單、不 seed 隨機
- [x] 1.2 [P] 記 D3 pin 常數（三層）：HF 鏡像 revision（CV_ZHTW_REV，content-addressed）、dev shard tar digest、每 clip 檔名清單與各 clip SHA-256（同 fetch-corpora.sh FLEURS_*/_SHA 風格）
- [x] 1.3 fetch-corpora.sh 加繁中區段（實作 corpora "zh/ja standard set is scriptable and verified" 的繁中側）：curl 鏡像 dev shard tar @ CV_ZHTW_REV → shard digest verify（parser 碰 bytes 前）→ 抽出選中 clip（MP3）→ per-clip afconvert 轉 16 kHz mono WAV（python3 wave 只吃 WAV，轉檔先於 concat）→ python3 concat 成組 + 內嵌 verbatim SRT（cue 時間用 clip_durations.tsv + 累計 offset）→ converted artifact digest verify → corpus add --language zh --name <組名>（zh 碼保留、語意=繁中）；官方 Data Collective bring-your-own-tarball 為文件化替代路徑

## 2. 移除簡體 — corpora "zh/ja standard set is scriptable and verified"（Simplified SHALL NOT be part）
- [x] 2.1 fetch-corpora.sh 刪除 FLEURS cmn_hans_cn（簡體 zh）整個區段（含 FLEURS_ZH_TAR_SHA / FLEURS_ZH_WAV_SHA / cmn_hans_cn TSV digest 常數與註解）——標準集不含簡體
- [x] 2.2 既有 store 若有簡體 zh measured rows：不主動清（本機歷史），但 baseline 不含簡體、gate 不跑簡體——簡體自然退場

## 3. en/ja 規模對齊 — design "D5 — en/ja 同步擴充到 ~20-30，三語言對稱" + design "D4 — 每語言拆 3-5 個中長度 corpus，不全串成一個" + corpora "English standard set is scriptable and verified"
- [x] 3.1 [P] ja：從 FLEURS ja_jp dev split（同既有 REV）多取 clip 到 ~20-30，分 3-5 組（D4），更新 pin（tar/TSV digest 沿用、加各組 converted artifact SHA）——D5 三語言對稱
- [x] 3.2 [P] en："English standard set is scriptable and verified" 的 3-5 corpora / 20-30 utterances：從 OSR 其他 Harvard list（voiptroubleshooter Open Speech Repository）或 FLEURS en 補到 ~20-30，分 3-5 組（D4），各組 digest pin

## 4. Regression baseline + gate — regression-benchmark "Machine-independent regression baseline" + "Regression gate fails on accuracy regression"
- [x] 4.1 建 benchmarks/baseline.json 實作 "Machine-independent regression baseline"，依 design "D1 — Baseline = repo 內 pinned `benchmarks/baseline.json`，只記 CER/WER" + "D2 — Gate model = 單一固定 reference WhisperKit model"：對固定 reference model（whisperkit large-v3-turbo）先跑一次三語言全 corpus，記每 corpus {corpus, language, model, metric, golden, tolerance}——只記 accuracy 不記速度；golden = 首次實測、tolerance 留餘裕（如絕對 CER +0.02）
- [x] 4.2 scripts/regression-gate.sh 實作 "Regression gate fails on accuracy regression"，依 design "D6 — regression gate script 沿用 validate-diarization.sh 範式"：確保語料已註冊 → 對 reference model 跑 benchmark 取每 corpus CER/WER → 讀 baseline.json 逐 corpus 比對 → 超 tolerance exit 1（印語言/golden/actual/diff）；缺 baseline 條目報 gate error 非靜默通過；速度差不 fail
- [x] 4.3 Tests/BestASRKitTests/RegressionBaselineTests.swift：baseline.json schema 合法性 + 比對邏輯單元測試（tolerance 邊界、缺條目報錯、只判 accuracy 不判速度）

## 5. Spec + 文件
- [x] 5.1 [P] corpora spec MODIFIED 套用（en + zh/ja standard set 語言組成 + 規模；繁中取代簡體）
- [x] 5.2 [P] regression-benchmark spec ADDED 套用（baseline + gate 兩 requirement）
- [x] 5.3 [P] README：三語言 benchmark 段落——「中文」明指繁體、regression gate 用法、machine-independent（只 gate 準確度不 gate 速度）說明

## 6. 收尾
- [x] 6.1 spectra validate + 全套件（swift test）綠
- [x] 6.2 regression-gate.sh live：未退步 build exit 0；人為改一個 golden 到不可達 → exit 1 並指出該 corpus（對應 "an accuracy regression fails loudly" scenario）
- [x] 6.3 fetch-corpora.sh live：corpus list 顯示三語言各 3-5 corpus、無簡體、繁中源 Common Voice zh-TW（對應 "one command registers Traditional Chinese and ja corpora" scenario）

## 7. 繁中 script 正規化（mid-apply 裁決，design "D7 — zh 的 CER 做 script 正規化（雙側 Hant→Hans，mid-apply 裁決 2026-07-05）"）
- [x] 7.1 TDD：ErrorRate/TextNormalizer 對 language zh 的 CER 比對前雙側 Hant→Hans（ICU StringTransform）；ja/ko/en 不動；spec 既有 CER example（今天天氣好）行為保持；新 scenario（簡體 hypothesis vs 繁體 reference → CER 0）；BenchmarkRunner 兩處 compute call site 傳 language；重播種 zh golden
