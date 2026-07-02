## Context

rewrite 現況：`rewrite<T: Encodable>` 全檔覆寫 encode(rows)。loadRaw 的壞行警告在重寫後失去對象（行已刪）。MeasurementRow 十二欄無 revision；append 站點（CommandCore benchmark 迴圈）持有 store 與 modelId。

## Goals / Non-Goals

Goals：壞行零刪失、量測列帶量測時 pin、舊資料無痛解碼。Non-goals 見 proposal。

## Decisions

### D1 — rewrite 保留機制（preserve-verbatim）

`rewrite<T: Codable>`（Encodable → Codable）：覆寫前讀既有檔，逐行試 decode T，**失敗行收集為 preserved bytes**；新 payload 寫完後原樣附回（順序：新 rows 在前、preserved 在後——JSONL 無序語意，讀取端本就逐行獨立）。保留行繼續在每次 load 觸發警告 = loud 契約的延續而非替代。不新增 API surface（Snapshot 不變）。

### D2 — provenance 來源（seeded 表為量測時真相）

`MeasurementRow.hfRevision: String?` 預設 nil（migration 與 legacy 路徑自動 nil）。append 站點在 measured 迴圈前 `store.load().models` 一次，以 modelId 查 seeded row 的 `hfRevision` 寫入——用「當下 seed 進 store 的表」而非 code-owned grid 常數，語意是「量測當下綁定的 pin」（正是 #15 DA 指出會漂移的那個時點事實）。

### D3 — 向後相容

optional + snake_case CodingKey：舊列（無 `hf_revision`）decode 為 nil；projection/routing 不讀此欄（純審計欄），零行為變更。

## Implementation Contract

- 壞行經 `upsert(corpus:)` 與 `seed(models:)` 後 byte-identical 倖存（測試鎖定）
- 量測列 append 後帶 seeded pin；無 pin 的 model（whisper.cpp 列）nil（測試鎖定 store 層；runner 端 wiring 由 #18 真實 benchmark 佐證）
- 161 tests 基線 + 新測試全綠
