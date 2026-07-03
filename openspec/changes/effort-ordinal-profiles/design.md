# Design — effort-ordinal-profiles

## Context

`Ranking.rank` 對兩軸 min-max 正規化後加權（`DataModels.RouterProfile` 提供權重），`ColdStartPrior` 用 `ModelRegistry.profileModels[profile]` 選 cold-start 候選，CLI 於 `CommandCore` 兩處 `RouterProfile(rawValue:)` parse。皆為序數化的既有掛點。

## D1 — 序數集與權重

low 0.267 / medium 0.5 / high 0.8 / xhigh 0.9 / max 1.0。low/medium/high 沿用舊 fast/balanced/accurate 的實測錨點（design-brief 四軸重正規化的血統，行為可對照）；xhigh=0.9 是 high 與 max 的中點級距；max=1.0 = 純 argmax（使用者裁決「不計任何時間要最準的」）。

## D2 — max 的 tie-break 顯式化

weight 1.0 時 speed 項消失，同 errorRate 候選同分；現行 `.sorted { $0.1 > $1.1 }` 非穩定排序 → 同分次序不可重現。改為顯式 total order：score desc → timesRealtime desc（快者勝，「不計時間」≠「偏好慢」）→ (backend, model, quantization) 字典序（決定性兜底）。所有檔位受益，非 max 專屬。

## D3 — `auto` sentinel 是 CLI 層預設，不是 RouterProfile case

關鍵：ArgumentParser 的 default value 使「使用者顯式傳 medium」與「未傳」不可區分。解法：`--profile` 預設字串 `auto`，於 CommandCore 解析——`auto` → 讀 DynamicHostState → medium（無壓力）或 low（壓力），解析理由進 explain；序數值 → 直接 parse。RouterProfile enum 保持 5 個純序數 case，router/ranking 層完全不知道 auto。顯式序數永不被動態狀態改寫（使用者裁決）。

## D4 — 動態狀態 = thermal + LPM，僅此二者

`ProcessInfo.thermalState`（≥ .serious 算壓力）+ `isLowPowerModeEnabled`。公開 API、同步讀取、可 seam 注入。CPU 瞬時負載與電量百分比不納入（噪聲高、不可重現；省電意圖已由 LPM 表達）——diagnose Residue 記載。probe 失敗（理論上 ProcessInfo 不會，但 seam 容許）→ 視為無壓力，偵測永不阻斷轉錄。

## D5 — cold-start 5-tier map：high/xhigh/max 刻意同列

low → tiny/base/small；medium → small/medium；high/xhigh/max → medium/large-v3-turbo/large-v3（同一列）。理由：cold start 無實測資料，序數的差異**只能**在 measured 加權中體現；沒有數據時偽造 xhigh/max 的差異（例如硬塞更大模型清單）是無根據的假精確。三檔同列 = 「都選記憶體放得下的最大模型」，誠實且與 memory-downgrade requirement 相容。

## D6 — 舊值硬錯誤 + 遷移對照

使用者裁決拒絕 alias 層。`RouterProfile(rawValue:)` guard 失敗時，若輸入 ∈ {fast, balanced, accurate} 錯誤訊息附「fast→low、balanced→medium、accurate→high（或要最準用 max）」；其他未知值列 auto+5 序數。pre-1.0、無外部使用者負擔。

## D7 — README 結構

使用者旅程序：Why → Install → Quick start（零 flag：auto 心智模型 = 機器能力 + 實測 store + 動態狀態）→ Profiles 契約表（檔位 × 權重語意 × 時間期望 × 適用場景）→ Benchmark workflow → Context calibration → **Diarization → Speaker identification（voices/、local-only 生物特徵警語）**→ explain → Commands 全參考 → How it works。
