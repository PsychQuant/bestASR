## Summary

移除 mlx-audio 第三 backend（engine、worker、協定與其 wiring），模型目錄（15 家族含 pin 資料）降級為 reference catalog 保留於 grid 與 `list-models` 展示。

## Motivation

使用者裁決（#20，逐字保留於 issue）：維持 Python venv + worker 行程 + 快速演進上游 API 的整合成本，超過對此 backend 的需求；「那裡面的模型list我要參考而已」。副作用分析（失去 parakeet 最佳量測點、#18/#16 連動 re-scope、store 舊量測自然濾除）已呈報並獲知情確認。

## Proposed Solution

刪除 `MLXAudioEngine` / `MLXWorkerProtocol` / `mlx_worker.py` 與對應測試；`BackendID` 回兩成員；修剪 Router（availability 鏈、family/size 推斷、mlx cold-start、pair-guard 訊息）、CommandCore（engines 名單、promptSupported 分支）、BenchmarkRunner（mlx 枚舉分支）、CLI help；`ModelGrid` mlx rows 保留並標 reference-only，`list-models` 標注「reference catalog — backend not bundled」；投影/路由對無 engine 的 backend 字串靜默濾除（測試鎖定）。

## Non-Goals

- 不動 BCNF store、corpora registry、`hfRevision` 欄位與 pin 資料、`fetch-corpora.sh` raw pin
- 不清使用者家目錄（venv / HF cache——清理指令附 closing summary）
- 不移除 store 既有 mlx 量測（append-only 歷史）
- 不改既有兩 backend 任何行為

## Alternatives Considered

- 保留 backend + runtime 版本 pin：已分析，使用者仍裁決移除（成本/需求比）
- 目錄搬 markdown 文件：捨棄——留在 grid 更活（機器可用、list-models 可見、復活成本低）

## Impact

- Affected specs: `mlx-audio-engine`（REMOVED 全 capability）、`model-grid` / `benchmark` / `asr-engine`（MODIFIED）
- Affected code:
  - Removed: Sources/BestASRKit/Engines/MLXAudioEngine.swift, Sources/BestASRKit/Engines/MLXWorkerProtocol.swift, Sources/BestASRKit/Engines/mlx_worker.py, Tests/BestASRKitTests/MLXAudioEngineTests.swift
  - Modified: Package.swift, Sources/BestASRKit/Models/DataModels.swift, Sources/BestASRKit/Models/ModelGrid.swift, Sources/BestASRKit/Models/ModelRegistry.swift, Sources/BestASRKit/Router/Router.swift, Sources/BestASRKit/CommandCore.swift, Sources/BestASRKit/Benchmark/BenchmarkRunner.swift, Sources/bestasr/BestASRCommand.swift, Tests/BestASRKitTests/RouterTests.swift, Tests/BestASRKitTests/DataModelTests.swift, Tests/BestASRKitTests/ModelGridTests.swift, Tests/BestASRKitTests/BenchmarkStoreTests.swift, README.md, CHANGELOG.md
