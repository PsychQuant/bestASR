## Why

bestASR 的核心價值主張是 benchmark-driven router——在多個候選模型上實測本機表現、選出最好的。#20 移除 mlx-audio backend 後，候選池鎖死在 Whisper 家族（whisperkit / whisper.cpp 都只能跑 Whisper 系模型），router 的「選最好」退化成「在 Whisper 大小變體之間選」。使用者裁決（#35）：「不是多個 backend，本來就應該有多個模型，從中選最好的」——catalog 裡的非 Whisper 家族應該可跑、可測、可被選，而不只是躺在 reference 目錄裡。

FluidAudio（0.15.4，#25 diarization 已 exact-pin）自帶 Parakeet ASR（TDT CoreML），提供一條**零新依賴**的路徑打通第一個非 Whisper 家族。本 change 的目標是端到端證明跨家族競擇機制；家族覆蓋面刻意漸進（#20 的教訓：覆蓋面的維運成本必須有 containment）。

## What Changes

- 新增 `ParakeetEngine`（第三個 `Engine` conformer）：包裝 FluidAudio `AsrManager`，模型按需下載、輸出映射為 `RawTranscription`；經 #36 的 `AudioNormalizer` seam 自動收 16 kHz mono
- `BackendID` 新增 `fluidParakeet = "fluid-parakeet"` case；`list-backends` 顯示第三個 backend 與可用性
- `ModelGrid`：新增 live 的 fluid-parakeet rows（parakeet 家族，priority 1）；原 mlx-audio parakeet row 維持 reference 不動（15 家族 reference catalog 完整保留）
- Router / availability 鏈：`fluid-parakeet` 進入候選枚舉；benchmark 可量測它；`recommend` / `transcribe` 依 measured 表現跨家族選擇
- Benchmark 對跨家族 hypothesis 統一走既有 `TextNormalizer` 後計 WER/CER（tokenizer 差異在文字層抹平）
- CLI `--backend` 值域擴充（`auto | whisperkit | whisper.cpp | fluid-parakeet`）

## Non-Goals

- **不**復活 mlx-audio backend（#20 裁決維持；Python venv / worker 協定不回來）
- **不**在本 change 納入中文 high-value 家族（Qwen3-ASR via MLX-Swift）——列 follow-up issue
- **不**設計通用 external-process engine 協定——一個家族尚未打通前設計通用協定是過度抽象（YAGNI），列 follow-up issue
- **不**動 15 家族 reference catalog 的語意（reference rows 仍不參與 benchmark 枚舉）
- **不**改變 effort profile（#29）語意；Parakeet 模型單一尺寸，profile 對其退化為 no-op 屬可接受

## Capabilities

### New Capabilities

- `parakeet-engine`: FluidAudio Parakeet TDT CoreML 引擎——第三個 Engine conformer，模型生命週期、按需下載、RawTranscription 映射

### Modified Capabilities

- `asr-engine`: BackendID 擴充為三成員；availability 語意涵蓋 FluidAudio 模型下載
- `asr-routing`: 候選枚舉涵蓋 fluid-parakeet；跨家族依 measured 排序
- `model-grid`: 新增 live fluid-parakeet rows；reference rows 語意不變
- `benchmark`: 跨家族 metric 可比性（統一 TextNormalizer）；fluid-parakeet 進入量測矩陣

## Impact

- Affected specs: parakeet-engine (new), asr-engine, asr-routing, model-grid, benchmark
- Affected code:
  - New: Sources/BestASRKit/Engines/ParakeetEngine.swift, Tests/BestASRKitTests/ParakeetEngineTests.swift
  - Modified: Sources/BestASRKit/Models/DataModels.swift（BenchmarkRunner 經評估無需修改——枚舉為 engine+grid 資料驅動）, Sources/BestASRKit/Models/ModelGrid.swift, Sources/BestASRKit/Models/ModelRegistry.swift, Sources/BestASRKit/CommandCore.swift, Sources/bestasr/BestASRCommand.swift, Tests/BestASRKitTests/RouterTests.swift, Tests/BestASRKitTests/ModelGridTests.swift
  - Removed: (none)

## Assumptions（unattended 決策，可挑戰）

- 第一家族選 Parakeet（零新依賴）而非中文最優家族：#35 驗收重點是「競擇機制」端到端，Parakeet 的英/歐語覆蓋足以證明機制；中文家族屬第二批（follow-up）
- 與 #36 stacked：本 change 實作 branch 以 idd/36-mp3-input-normalization 為 base（新 engine 依賴 AudioNormalizer 的 16 kHz mono 保證）
- FluidAudio AsrManager API 可映射 RawTranscription（依 0.15.4 公開 API；design 階段驗證形狀）
