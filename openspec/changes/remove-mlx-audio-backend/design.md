## Context

#20 裁決移除三 backend 中的 mlx-audio；目錄留 reference。前置 change 已歸檔（歷史保存），本 change 走 REMOVED capability。

## Goals / Non-Goals

Goals：程式碼零 mlx 執行路徑殘留（編譯器 + grep 掃尾）；grid 目錄與 pin 資料完整保留且 list-models 可見；舊 store 量測靜默濾除有測試鎖定。Non-goals 見 proposal。

## Decisions

### D1 — Grid 語意：reference catalog

mlx rows 留在 `ModelGrid`（backend 欄為字串，無需 enum 成員）；`priority` 降級為「歷史挑選層級」敘述性欄位；`verified`/`hfRepo`/`hfRevision` 維持資料意義（未來復活即用）。`list-models` 段標題改「mlx-audio reference catalog (backend not bundled)」。

### D2 — 無 engine backend 的濾除

投影照常輸出 backend 字串 "mlx-audio" 的 BenchmarkRecord；Router 以 `BackendID(rawValue:)` 失敗自然濾除（既有行為，補測試鎖定：store 含 mlx 量測時 recommend 不 crash、不選 mlx、fallback 正常）。

### D3 — 刪除順序

先刪測試再刪實作最後刪 enum 成員，讓編譯器逐層指出殘留 reference；`git rm` + build 迭代。

## Implementation Contract

- `swift build` 零 error；`grep -ri "mlxaudio\|mlx_worker\|MLXWorker" Sources/ Tests/` 僅剩 ModelGrid 目錄資料與註解
- `list-models` 實跑顯示 reference 段；`benchmark`（雙 backend）實跑正常；store 舊 mlx 量測在 `recommend` 下被濾除（實跑 + 測試）
- 全套測試綠
