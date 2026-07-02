## Context

FLEURS live probe（2026-07-02）：非 gated（302 → 公開 CDN）；dev split zh 207MB / ja 171MB；TSV 佈局 `id⇥檔名⇥逐字稿`；revision 由 redirect 取得可 pin。原始 wav 為 float32（wave format 3）——python stdlib `wave` 不吃，afconvert LEI16@16000 轉整數 PCM。

## Goals / Non-Goals

Goals：可重現（全鏈 pin）、可下載（無 auth）、license 乾淨（CC-BY-4.0 附 attribution 註解）。Non-goals 見 proposal。

## Decisions

### D1 — 選句 deterministic：TSV 序前 3 個相異句 id、各取首錄音（zh 29.6s / ja 37.9s，與 en 集量級一致）
### D2 — 一語言一 corpus（串接單檔 + 多 cue SRT），沿 en 樣式；非一句一 corpus（避免 benchmark 成本×N）
### D3 — SRT 逐字稿內嵌 script（輸入 pinned ⇒ 內容 deterministic，同 jfk/OSR 慣例）；cue 時間 = 轉檔後實測時長累加
### D4 — 供應鏈：revision pin + raw-tar digest 先驗（#15 parse-before-verify 教訓）+ 轉檔後 digest；tar 用後即刪（~400MB 不留家目錄）

## Implementation Contract

- `bash scripts/fetch-corpora.sh` 全程通過並註冊 zh+ja（live 已證：fleurs-cmn-dev3 29.6s / fleurs-ja-dev3 37.9s）
- 真實 benchmark 後 `recommend --language zh|ja` 回 measured（執行證據附 issue）
- `spectra validate` 綠
