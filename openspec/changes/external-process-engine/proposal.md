## Why

#51（使用者裁決 2026-07-06：立即設計）：候選池僅限編譯進 binary 的 Swift engines，reference catalog 的 15 家族（Qwen3-ASR、Canary、Voxtral、MMS…）多數無 Swift-native 實作、逐家族原生整合不 scale。使用者明確需求：「現在很多模型比 whisper 好」——這些模型正是 mlx-audio 承載的家族。#20 移除 mlx-audio 內建 backend 的理由（Python venv 滲入、worker 生命週期、上游 churn）由本協定的 containment 設計正面回應。

## What Changes

- **新 capability `external-engine-protocol`**：任何外部可執行檔符合協定即可作為 engine——bestASR 以 argv 陣列 spawn（絕不經 shell），adapter 於 stdout 輸出單一 JSON（`protocol` 版本欄、`text`、`duration`、選配 `segments`），非零 exit + stderr = 失敗 → TranscriptionError
- **`ExternalProcessEngine`**（Engine conformer）：subprocess spawn、timeout（音長比例+常數下限）、JSON 解析驗證、fail-loud 錯誤映射
- **註冊**：`~/.bestasr/engines.json`（id→command argv）；`BackendID` v1 加一個 `.mlxAudio` case（enum 保持封閉；未來每個新工具 = 一個 case 的小 diff）
- **grid reference rows 升級**：mlx-audio 的 15 家族 rows（hfRepo＋pinned revision 現成）在 adapter 註冊且可用時成為 runnable 候選；未註冊時維持 reference-only（現行為不變）
- **第一 consumer**：`adapters/mlx-audio/` adapter script + venv bootstrap（`uv venv`＋`pip install mlx-audio`，全部住在 `~/.bestasr/adapters/`，bestASR 本體零 Python 依賴）＋一家族端到端實測

## Non-Goals

- 不做常駐 worker/server mode（協定 v2 空間；v1 每呼叫一 process，RTF 誠實含 spawn＋model 載入——external 家族的結構性量測差異 spec 明載）
- 不動既有 Swift engines 與其量測數據
- 不逐家族寫 adapter（mlx-audio 一個 adapter 覆蓋其全 catalog）

## Capabilities

### New Capabilities

- `external-engine-protocol`: 協定契約（呼叫形狀、JSON schema、錯誤面、timeout、containment、量測可比性語意）

### Modified Capabilities

- `benchmark`: 候選枚舉規則泛化——有 engine 的 backend 才枚舉（bundled 或 registered external）
- `asr-routing`: reference-only 排除規則放寬——已註冊 external adapter 的 backend rows 可枚舉
- `model-grid`: mlx-audio rows 的 runnable 條件描述

## Impact

- Affected specs: external-engine-protocol（新）, asr-routing, model-grid, benchmark
- Affected code:
  - New: Sources/BestASRKit/Engines/ExternalProcessEngine.swift, Sources/BestASRKit/Engines/ExternalEngineRegistry.swift, adapters/mlx-audio/bestasr-mlx-adapter.py, adapters/mlx-audio/setup.sh, Tests/BestASRKitTests/ExternalEngineTests.swift
  - Modified: Sources/BestASRKit/Models/DataModels.swift（BackendID + .mlxAudio）, Sources/BestASRKit/Models/ModelGrid.swift, Sources/BestASRKit/Models/ModelRegistry.swift, Sources/BestASRKit/Router/Router.swift, Sources/BestASRKit/CommandCore.swift, README.md, CHANGELOG.md
