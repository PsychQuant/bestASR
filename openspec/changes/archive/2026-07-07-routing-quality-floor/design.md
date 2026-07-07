## Context

#64：`Ranking.rank` per-record min-max＋profile 加權；Router 直接餵 raw records。單筆滿分與極端爛分都無防禦。store 現有數據（tiny mean 0.274／單筆 0.0；parakeet zh 0.935）即為復驗基準。

## Goals / Non-Goals

**In**：Router 端聚合＋門檻、asr-routing delta、TDD＋live 復驗。
**Out**：corpus 分層、Ranking.rank 本體、report 顯示。

## Decisions

### D1 — 聚合在 Router、不在 Ranking

Ranking.rank 是 benchmark report 與 Router 共用的純排序原語；report 的輸入天然每 model 一筆（單次 run），聚合對它是無意義的複雜度。Router 的 usable 池才有多 corpus/多 runs 混雜——聚合是 routing 語意。Deletion test：拿掉聚合 → tiny 單筆 0.0 再度奪冠。

### D2 — mean 等權聚合，合成代表記錄

per-record 等權（非 per-corpus）——簡單、可解釋、單調（多量測收斂真實水準）。合成 BenchmarkRecord：errorRate/timesRealtime=mean、measuredAt=latest、其餘欄位取 latest 記錄。reason 行揭露聚合基數（「mean of N runs」）。

### D3 — 品質門檻 0.5 只擋自主推薦

mean error rate > 0.5 = 每兩個單位就錯一個以上，轉錄實用價值為負——不該被「自主」推薦。門檻後池空 → cold-start prior（既有 fallback，行為連續）。顯式鎖定 backend = 使用者意志：不剔除，但 reasons 附品質警告（沿 #50 M6 慣例）。門檻是常數（非 profile 相依）——它是「可用性下限」不是「偏好權重」。

## Risks / Trade-offs

- mean 稀釋：難 corpus 首測會拉高既有候選的 mean——公平（所有候選同受），且比單筆最佳的病態好
- 0.5 武斷性：spec 明載語意（自主推薦的可用性下限）；調整是一行常數

## Migration Plan

行為變更：既有 store 下 zh 推薦從 parakeet→sensevoice、en 從 tiny→large-v3-turbo（此即修復目標，live 復驗鎖定）。Rollback = revert。

## Open Questions

（無）
