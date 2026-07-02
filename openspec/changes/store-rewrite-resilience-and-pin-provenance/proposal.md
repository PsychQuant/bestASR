## Why

#16（#14 verify L-14/L-10 + #15 verify DA 追記）：(1) `BenchmarkStore.rewrite()` 以「可解析列整表重寫」——`loadRaw()` 對壞行只警告，但 `upsert(corpus:)`/`seed(models:)` 重寫時壞行**永久消失**，spec「Corrupt rows degrade loudly, not fatally」只鎖了 load 面，rewrite 面是資料刪失破口；(2) `MeasurementRow` 無 pin provenance——`hf_revision` 只活在 models 目錄表，而 `seed()` 每次 benchmark 整表重寫，pin bump 後歷史量測被靜默重新關聯到新 pin，「這筆數字在哪個 snapshot 上量的」不可考。

## What Changes

1. `BenchmarkStore.rewrite()`：重寫前掃描既有檔案，無法解碼的行**原樣保留**（附回檔尾）——載入警告因此持續存在（loud 不變），使用者資料永不因「我們讀不懂」而被刪
2. `MeasurementRow.hfRevision: String?`（`hf_revision`）：量測時事實；benchmark append 站點自 seeded models 表解析當下 pin 寫入；legacy migration 與舊列 nil（向後相容，無 migration）
3. spec deltas：benchmark-store MODIFIED ×2（Corrupt-rows requirement 延伸 rewrite 保留；Append-only measurements 增 provenance 條款）

## Impact

- Affected specs: benchmark-store (MODIFIED ×2)
- Affected code: Sources/BestASRKit/Store/{BenchmarkStore,StoreTables}.swift、Sources/BestASRKit/CommandCore.swift（append 站點）、Tests/BestASRKitTests/BenchmarkStoreTests.swift
- Non-goals：grid 尺寸鋪滿（#20 後降為 reference 資料維護，已 re-scope 移出）；runner 端 wiring 的端對端斷言由 #18 的真實 benchmark 執行佐證（該輪量測列應帶 hf_revision）
