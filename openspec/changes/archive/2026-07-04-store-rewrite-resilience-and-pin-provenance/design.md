## Context

rewrite 現況：`rewrite<T: Encodable>` 全檔覆寫 encode(rows)。loadRaw 的壞行警告在重寫後失去對象（行已刪）。MeasurementRow 十二欄無 revision；append 站點（CommandCore benchmark 迴圈）持有 store 與 modelId。

## Goals / Non-Goals

Goals：壞行零刪失、量測列帶量測時 pin、舊資料無痛解碼。Non-goals 見 proposal。

## Decisions

### D1 — rewrite 保留機制（preserve-verbatim）

`rewrite<T: Codable>`（Encodable → Codable）：覆寫前讀既有檔，逐行試 decode T，**失敗行收集為 preserved bytes**；新 payload 寫完後原樣附回（順序：新 rows 在前、preserved 在後——JSONL 無序語意，讀取端本就逐行獨立）。保留行繼續在每次 load 觸發警告 = loud 契約的延續而非替代。不新增 API surface（Snapshot 不變）。

**Byte-level，非 String-level（verify F1/F13 收斂）**：讀取用 `Data` + 0x0A 切行——String round-trip 會把非 UTF-8 損壞靜默丟失（恰是契約最想保住的情況）；檔案存在但讀不到 → **throw**（絕不盲目覆寫讀不到的檔）。`loadRaw` 同步改 byte-level：非 UTF-8 行以警告跳過，而非整表靜默載空。

### D2 — provenance 來源（seeded 表為量測時真相）

`MeasurementRow.hfRevision: String?` 預設 nil（migration 與 legacy 路徑自動 nil）。append 站點以 **(backend, size, quantization)** 對「本次 seed 的 in-memory rows」查 seeded row（`CommandCore.seededRow` 可測 helper）——**row 自帶 family 與 pin**，同時修正量測 primary key 的 family hardcode（verify DA：`family="whisper"` 寫死會讓未來非 whisper 家族的 modelId 錯 key）。verify F12 收斂：`ModelGrid.rows` 幾行前才逐字 seed 進 store，in-memory 陣列即 as-seeded 表，免掉整個 store（含量測史）的重讀。查無 row → fallback 舊 key 構造 + pin nil。migration 的 family 對齊 live 路徑（legacy 時代 whisper-only），修掉「同邏輯模型雙 key、projection 永不 supersede」的既有洞。

### D3 — 向後相容

optional + snake_case CodingKey：舊列（無 `hf_revision`）decode 為 nil；projection/routing 不讀此欄（純審計欄），零行為變更。

## Implementation Contract

- 壞行經 `upsert(corpus:)` 與 `seed(models:)` 後 byte-identical 倖存（測試鎖定）
- 量測列 append 後帶 seeded pin；無 pin 的 model（whisper.cpp 列）nil（測試鎖定 store 層；runner 端 wiring 由 #18 真實 benchmark 佐證）
- 161 tests 基線 + 新測試全綠
