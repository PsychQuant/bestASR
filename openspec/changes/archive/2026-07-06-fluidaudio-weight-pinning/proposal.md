## Why

#52：SwiftPM `exact: 0.15.4` 只錨定 FluidAudio 的 code，權重實際走 HF `resolve/main`（無 revision pin、無 checksum）。HF 帳號被劫或惡意 push main 會靜默傳播到所有使用者。與 #15/#19 的 pin 紀律結構性不相容，README 目前只能明文 trade-off。

## What Changes

- 新 capability `weight-pinning`：`WeightVerifier` 於模型下載後、load 前，對 model cache 目錄逐檔 SHA256 對照 repo 內 `weights-manifest.json`；mismatch **fail-loud**（throw）；manifest 未收錄的 model 印警告放行（TOFU 首測窗口）
- 掛 3 個 seam：ParakeetEngine、DiarizationEngine、SpeakerEnroller 的下載呼叫點
- `scripts/pin-weights.sh`：maintainer 對本機 cache 產生/更新 manifest（首測信任錨定）
- 首版 manifest 以本機現有 cache（3 model repos、42 檔）實測產出入 repo；README 供應鏈段由「trade-off 聲明」升級為「機制描述」

## Non-Goals

- 不防「首次下載即已污染」（信任錨定於 maintainer 首測機器——spec 明載此誠實邊界）
- 不繞過 FluidAudio resolver 自行下載（維護 HF 檔案清單成本高、失去 auto-recovery）
- 上游 revision-pin PR 另案，不阻塞

## Capabilities

### New Capabilities

- `weight-pinning`: FluidAudio 權重完整性驗證（TOFU→pin、fail-loud on mismatch）

### Modified Capabilities

(none — 掛點是實作細節，asr-engine/diarization spec 的既有 normative 行為不變；驗證失敗的 fail-loud 契約由新 spec 承載)

## Impact

- Affected specs: weight-pinning（新）
- Affected code:
  - New: Sources/BestASRKit/Supply/WeightVerifier.swift, Sources/BestASRKit/Supply/weights-manifest.json（resource）, scripts/pin-weights.sh, Tests/BestASRKitTests/WeightVerifierTests.swift
  - Modified: Sources/BestASRKit/Engines/ParakeetEngine.swift, Sources/BestASRKit/Diarize/DiarizationEngine.swift, Sources/BestASRKit/Diarize/SpeakerEnroller.swift, Package.swift（resource 宣告）, README.md, CHANGELOG.md
