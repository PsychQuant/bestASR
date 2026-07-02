## Why

bestASR 的模型池限於 Whisper 家族（WhisperKit、whisper.cpp）。mlx-audio 在 Apple Silicon 原生 MLX 上提供 15 個 STT 家族（Parakeet、Qwen3-ASR、Voxtral、Moonshine、Canary、MMS…），使用者要求（#14）把它們納入同一把 benchmark 量尺：「grid 全建、先跑表現最好的；紀錄做成 BCNF、每筆 JSON；best = 知道什麼時候用什麼最好；語料先 en/zh/ja」。現行 `benchmarks.json` 單張扁平表的 functional dependencies 未收斂（機器事實、模型目錄事實混在量測筆內），無法表達「已枚舉未量測」的 grid 狀態。

## What Changes

1. **MLXAudioEngine（第三 backend）**：持久 stdin/stdout JSON-lines Python worker（每模型一個、CreateOnceStore 快取 + keep-current eviction 沿用），venv 由 uv 管理（`~/.bestasr/mlx-env`），availability 誠實偵測 + 安裝指引。
2. **Model Grid**：ModelRegistry 演化為全家族目錄（backend × family × size × quantization → hf_repo/languages/est_memory/priority），15 家族全枚舉；priority 1 = 先行集（mlx-Whisper large-v3-turbo 4bit、Parakeet 0.6B、Qwen3-ASR small、Moonshine base），benchmark 預設掃 priority 1、`--all-grid` 全開。
3. **BCNF 儲存**：`~/.bestasr/store/` 四張 JSONL 表——machines / models(grid) / corpora / measurements（append-only；路由讀每 (model,corpus,machine) 最新）；舊 `benchmarks.json` 一次性遷移（.bak 保留）；Router/Ranking/Report 改讀 join 投影。
4. **Corpora registry**：`corpus add/list` 子命令 + en 標準集抓取腳本（jfk、OSR，sha256 驗證）；zh/ja 以使用者自備素材註冊。

## Non-Goals

- mlx-audio 的 TTS/STS/診斷類模型（bestASR 是 ASR 路由器）
- 9B/24B 級模型的實測（入 grid priority 3，不在本 change 煙測範圍）
- REST server 呼叫面、mlx-audio-swift（現僅 TTS）
- zh/ja 標準語料的自動下載（v1 = user-supplied via corpus add；殘留於 issue Residue）
- 分散式/多機 store 同步

## Capabilities

### New Capabilities

- `mlx-audio-engine`: MLX backend——worker 協定、venv 偵測、模型解析、輸出正規化
- `model-grid`: 全家族目錄 schema、priority 先行集、枚舉語意（「未量測」= measurements 無 row）
- `benchmark-store`: BCNF 四表 JSONL 儲存、append-only 量測、最新投影、舊檔遷移
- `corpora`: 語料 registry、corpus add/list、en 標準集抓取、sha256 完整性

### Modified Capabilities

- `asr-engine`: 第三 backend 納入 backend 集合與 availability 契約
- `benchmark`: 枚舉改自 grid（priority 過濾）、量測寫入 store 取代單檔 upsert
- `asr-routing`: 讀 store 最新投影、per-language 排名明確化

## Impact

- Affected specs: 上列 4 新 + 3 修改
- Affected code:
  - New: `Sources/BestASRKit/Engines/MLXAudioEngine.swift`, `Sources/BestASRKit/Engines/mlx_worker.py`, `Sources/BestASRKit/Store/BenchmarkStore.swift`, `Sources/BestASRKit/Store/StoreTables.swift`, `Sources/BestASRKit/Models/ModelGrid.swift`, `Sources/BestASRKit/Corpora/CorpusRegistry.swift`, `scripts/fetch-corpora.sh`, 對應測試檔
  - Modified: `Sources/BestASRKit/Models/ModelRegistry.swift`, `Sources/BestASRKit/Benchmark/BenchmarkRunner.swift`, `Sources/BestASRKit/Benchmark/BenchmarkCache.swift`（讓位/遷移）, `Sources/BestASRKit/Benchmark/BenchmarkReport.swift`, `Sources/BestASRKit/Router/Router.swift`, `Sources/BestASRKit/Router/Ranking.swift`, `Sources/BestASRKit/CommandCore.swift`, `Sources/bestasr/BestASRCommand.swift`, `README.md`, `CHANGELOG.md`
  - Removed: (none——BenchmarkCache 保留為遷移讀取器後標記 deprecated)
