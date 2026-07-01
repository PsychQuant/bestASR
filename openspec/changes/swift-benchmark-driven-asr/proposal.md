## Summary

把 bestASR 從 Python 跨平台 heuristic 路由器，re-platform 成 **Apple Silicon 專屬的 Swift 原生 CLI**，並把路由核心從「靜態特性表猜測」升級為「**benchmark 實測驅動**」：新增 `bestasr benchmark` 指令，對 (backend × model × 量化) 候選在使用者機器上實測 CER/WER + RTF + 記憶體，結果快取後餵給 `recommend` / `transcribe`。

## Motivation

使用者定調（issue #2 diagnosis + discuss 結論，2026-07-02）：

1. **定位改變**：bestASR 主要服務 Apple Silicon / macOS。Swift 原生（WhisperKit + whisper.cpp）帶來 CoreML/ANE 整合、單一 binary 發布、原生啟動速度；Python 版的 CUDA/faster-whisper 路徑對此定位是 dead weight。
2. **「best」不能用猜的**：Python 版 design D2 用靜態特性表估算，推薦本質是分類猜測。改為在使用者機器上實測後，`--explain` 從「medium 被分類為 balanced」升級成「你這台機器上 large-v3-turbo 實測 CER 5.2%、12x realtime」——推薦準確與解釋清楚（專案護城河）同時強一個量級。
3. **多 backend 因 benchmark 而成立**：WhisperKit（CoreML/ANE 速度與系統整合）vs whisper.cpp（GGUF 模型/量化彈性）是真實的取捨，正是 benchmark 要量、router 要選的東西。

## Proposed Solution

依 discuss 拍板（Q1–Q4 + benchmark 升核心）：

- **Swift Package**（SPM）：library `BestASRKit` + executable `bestasr`（swift-argument-parser）。arm64-only、macOS 14+。
- **Backends**：WhisperKit（primary）+ whisper.cpp（secondary，C interop）。不含 mlx-swift（與 WhisperKit 底層 MLX 重疊）。
- **Benchmark（新核心能力）**：`bestasr benchmark <audio> --reference <ground_truth.srt>` → 枚舉本機可用候選 (backend × model × 量化) → 逐一轉錄 → 對 `.srt` ground truth 算 **CER（中文）/ WER（英文）**、RTF（實測速度）、峰值記憶體 → 排名報表 → 寫入機器層級快取。
- **Router 兩層**：有 benchmark 快取 → 以 profile 權重對實測數據排名；無快取（cold start）→ 靜態 prior fallback（沿用 profile 候選清單 + 記憶體降級鏈），並提示使用者跑 benchmark。
- **Detection**：Apple 硬體（晶片名、unified memory、ANE、macOS 版本，經 sysctl / ProcessInfo）+ 音訊探測改用 AVFoundation（移除 ffmpeg 相依）。移除 CUDA / VRAM / AVX 偵測。
- **`.srt` 雙向**：維持輸出格式之一，同時成為 benchmark 的 ground-truth 輸入（解析歸屬 benchmark capability）。
- **舊 Python 實作**：整包移入 archive 資料夾保存（唯一跨平台參考實作），不刪除。

## Non-Goals

範圍排除與否決方案記錄於 design.md 的 Goals / Non-Goals 區塊（Intel Mac、Linux/Windows、mlx-swift backend、即時串流、diarization、雲端 API、標準 benchmark 資料集內建等）。

## Alternatives Considered

- **維持 Python 跨平台**：路由價值最大化於跨平台分歧，但與使用者定調（Apple 優先、原生體驗、Swift 生態）不合。否決。
- **單一 WhisperKit backend**：最簡單，但 router 變 pass-through（deletion test 不過），「智慧路由器」身分蒸發成「WhisperKit CLI 包裝」。否決。
- **三 backend（含 mlx-swift）**：mlx-swift 與 WhisperKit（底層已用 MLX）重疊，無差異化價值，白養測試矩陣。否決。
- **繼續靜態特性表（不做 benchmark）**：推薦仍是猜測，「best」名不符實；使用者明確要求「大量磨模型做 benchmark、ground truth 用 .srt」。否決。

## Capabilities

### New Capabilities

- `benchmark`: 對本機可用 (backend × model × 量化) 候選實測轉錄品質與速度——解析 `.srt` ground truth、計算 CER/WER（依語言自動選）、RTF 與峰值記憶體、排名報表、機器層級結果快取供 router 消費。

### Modified Capabilities

- `asr-routing`: 由「跨平台規則決策表 + 靜態特性表」改為「benchmark 實測排名為主、靜態 prior 為 cold-start fallback」；backend 集合改為 whisperkit / whisper.cpp；解釋內容引用實測數據。
- `system-detection`: 移除 CUDA / VRAM / AVX / ffmpeg 偵測；改為 Apple Silicon 硬體輪廓（晶片、unified memory、ANE、macOS 版本）；音訊探測改 AVFoundation。
- `asr-engine`: backend 實作集合由 faster-whisper / whisper.cpp / mlx-whisper 改為 whisperkit / whisper.cpp；介面契約（可用性偵測、正規化 Transcript、錯誤浮出）不變。
- `cli`: 指令面新增 `benchmark`；`recommend` 輸出標註資料來源（實測 vs cold-start prior）並在有快取時附實測數據。

## Impact

- Affected specs: benchmark（新增）、asr-routing、system-detection、asr-engine、cli（修改）；transcript-output 不變。
- Affected code:
  - New:
    - Package.swift
    - Sources/BestASRKit/Models/DataModels.swift
    - Sources/BestASRKit/Models/ModelRegistry.swift
    - Sources/BestASRKit/Detect/SystemDetector.swift
    - Sources/BestASRKit/Detect/AudioProber.swift
    - Sources/BestASRKit/Detect/Language.swift
    - Sources/BestASRKit/Engines/Engine.swift
    - Sources/BestASRKit/Engines/WhisperKitEngine.swift
    - Sources/BestASRKit/Engines/WhisperCppEngine.swift
    - Sources/BestASRKit/Benchmark/SRTParser.swift
    - Sources/BestASRKit/Benchmark/TextNormalizer.swift
    - Sources/BestASRKit/Benchmark/ErrorRate.swift
    - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
    - Sources/BestASRKit/Benchmark/BenchmarkCache.swift
    - Sources/BestASRKit/Router/Router.swift
    - Sources/BestASRKit/Router/ColdStartPrior.swift
    - Sources/BestASRKit/Output/TranscriptWriter.swift
    - Sources/bestasr/BestASRCommand.swift
    - Tests/BestASRKitTests/DataModelTests.swift
    - Tests/BestASRKitTests/DetectionTests.swift
    - Tests/BestASRKitTests/MetricsTests.swift
    - Tests/BestASRKitTests/EngineTests.swift
    - Tests/BestASRKitTests/BenchmarkTests.swift
    - Tests/BestASRKitTests/RouterTests.swift
    - Tests/BestASRKitTests/OutputTests.swift
    - Tests/BestASRKitTests/CLITests.swift
  - Modified:
    - README.md
  - Moved（Python 實作整包遷入 archive 保存,非刪除）:
    - bestasr/ → archive/python/bestasr/
    - tests/ → archive/python/tests/
    - examples/ → archive/python/examples/
    - pyproject.toml → archive/python/pyproject.toml
  - Removed: (none)
- Dependencies:
  - WhisperKit（SPM,Apple Silicon CoreML/MLX ASR）
  - whisper.cpp（C interop,GGUF 量化模型）
  - swift-argument-parser（CLI）
  - AVFoundation / Accelerate（系統框架,音訊探測與計算）
