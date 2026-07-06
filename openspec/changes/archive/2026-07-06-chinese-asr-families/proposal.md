## Why

#50：#35 打通跨家族競擇後，中文候選池仍只有 Whisper。FluidAudio 0.15.4（已 exact-pinned）自帶 Paraformer（zh 專用 large）與 SenseVoice（small；zh/ja/yue/en/ko）兩個中文 high-value 家族——零新依賴，照 ParakeetEngine 模板即可接線。使用者明確表達核心關切是「多模型而非全 whisper」，中文是主場景。

## What Changes

- 兩個新 backend：`fluid-paraformer`（ParaformerManager，zh）與 `fluid-sensevoice`（SenseVoiceManager，多語含 zh/ja）——Engine conformer 沿 ParakeetEngine 模板（seam protocol + CreateOnceStore + fail-loud TranscriptionError 映射）
- 兩家族輸出為純文字（無 confidence／token timings）→ raw segment 為單段全文（duration 由 AudioProber），spec 明載此家族限制（SRT 為單一 cue；benchmark 全文 CER 不受影響）
- SenseVoice language hint：zh/ja/yue/en/ko → 對應 Int32，其他/未指定 → auto
- ModelGrid live rows ×2、Router `availableOrdered` 擴充、`--backend` help 動態值域自然帶入；**不加 hard language gate**（與 #35 同——靠 measured 數據自然路由）
- **zh-TW 實測**（issue acceptance）：cv-zhtw 套件對兩家族跑 CER 對照 whisper baseline，數字與輸出字系（簡/繁）觀察入 PR

## Non-Goals

- 不做 s2t 交付後處理／script-preference 路由因素（簡繁錯位另案；CER 比較已由 #34 fold 解決）
- 不動 Qwen3-ASR via MLX-Swift（僅當本輪實測品質不足才啟動）
- 不掛 WeightVerifier（本 branch 基 main 尚無 #52；merge 後補 one-liner——residue）

## Capabilities

### New Capabilities

- `chinese-asr-engines`: fluid-paraformer 與 fluid-sensevoice 兩個 Engine conformers（含 no-timings 家族限制的 normative 描述）

### Modified Capabilities

- `model-grid`: live rows 從單一 fluid-parakeet 擴為三個 FluidAudio backends

## Impact

- Affected specs: chinese-asr-engines（新）, model-grid
- Affected code:
  - New: Sources/BestASRKit/Engines/ParaformerEngine.swift, Sources/BestASRKit/Engines/SenseVoiceEngine.swift, Tests/BestASRKitTests/ChineseEnginesTests.swift
  - Modified: Sources/BestASRKit/Models/DataModels.swift（BackendID ×2）, Sources/BestASRKit/Models/ModelGrid.swift, Sources/BestASRKit/Models/ModelRegistry.swift, Sources/BestASRKit/Router/Router.swift, Sources/BestASRKit/CommandCore.swift, Tests/BestASRKitTests/（Router/DataModel/ModelGrid 斷言）, README.md, CHANGELOG.md
