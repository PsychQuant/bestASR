## Why

#64：多模型量測資料湧入後（#50/#53），live `recommend` 出現病態——zh 推薦 CER 93.5% 的 parakeet（273× 快靠 speed 權重奪冠）、en 推薦 whisper tiny（11 秒 jfk 單筆 WER 0.0 輾壓 81min 真實語料的 9.1%）。兩病根：records 無候選聚合、無品質下限。多模型時代的路由正確性核心。

## What Changes

- `Router.recommend` 的 measured 路徑：rank 前把 usable records 按 (backend, model, quantization) **聚合**（errorRate/timesRealtime 取 mean，等權 per record；合成單筆代表，measuredAt 取 latest）
- **品質門檻**：聚合後 mean error rate > 0.5 者從自主排序剔除；剔除後池空 → 自然落 cold-start prior（既有路徑）；顯式 backendOverride 鎖定不受門檻限制（沿 #50 的 unverified 警告慣例，附品質警告）
- `Ranking.rank` 不動——benchmark report（單次 run 每 model 一筆）語意不受擾

## Non-Goals

- corpus 難度分層／共同交集正規化（完整可比性——residue，另案設計）
- benchmark report 的顯示邏輯（報告該顯示全部量測）

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `asr-routing`: 「Rank candidates by measured benchmark data」補聚合與品質門檻 normative

## Impact

- Affected specs: asr-routing
- Affected code:
  - Modified: Sources/BestASRKit/Router/Router.swift, Tests/BestASRKitTests/RouterTests.swift, CHANGELOG.md
