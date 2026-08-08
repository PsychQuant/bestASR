## Summary

把 context 的 prompt token 預算從全域寫死的 200 改為**由所選引擎宣告的能力**，並讓不支援 prompt 的後端停止宣稱自己注入了 context。

## Motivation

`PromptRenderer.defaultTokenBudget = 200` 是單一全域常數，套用到所有 backend。但 prompt 能力是**逐引擎**的性質：`Engine` 是 public protocol，目前有 6 個 conformer，其中只有 `WhisperKitEngine` 與 `WhisperCppEngine` 真的消費 prompt；`ParakeetEngine`、`AppleSpeechEngine`、`ChineseFamilyEngine`、`ExternalProcessEngine` 完全不讀它。

對那 4 個引擎，整套 render 照跑、截斷照發生、`injected (N)` 照印——然後產物被丟棄。**系統宣稱做了它沒做的事。**

這不是設計潔癖。2026-08-07 轉錄一批學術會議錄音時，`recommend` 在 `high` profile 選出完全不吃 prompt 的 fluid-parakeet，CLI 仍印出 `injected (49)` / `truncated (53)`：

| 目標詞 | parakeet ＋ context | whisper ＋ context |
|---|---|---|
| Joint Thurstonian | 「during Sonya」 | 「Joint Thornia Models」 |
| Likert | 「the scale or L F」 | — |

兩個詞都在「已注入」的 49 個裡，parakeet 命中 0。使用者據 `injected (N)` 去精簡詞表，是白工。截斷也是真的發生的：102 項只注入 49、截斷 53，其中 8 個 phrase 因預算耗盡被整類丟棄——對不吃 prompt 的引擎而言，這整段取捨毫無意義。

## Proposed Solution

1. `Engine` protocol 增加 prompt 能力宣告，**二態**：`unsupported` 或 `supported(maxTokens:)`。
2. 6 個 conformer 各自宣告：兩個 whisper backend 為 `supported(224)`，其餘 4 個為 `unsupported`。
3. `PromptRenderer.render` 的預算由所選引擎提供，`defaultTokenBudget` 不再擔任全域預設。
4. 引擎宣告 `unsupported` 時**整段跳過 render**，explain 明講「此後端不支援 context biasing」，不印 `injected (N)`。
5. `recommend` / routing 在偵測到 context 目錄存在時，把 prompt 支援度納入選型；至少在選中 `unsupported` 引擎時警告。

上限 224 已由實證收斂：`whisper-cli --help` 明載 `--prompt PROMPT (max n_text_ctx/2 tokens)`，Whisper 的 `n_text_ctx = 448` → 224，與 `WhisperKitEngine.clampedPromptTokens(limit: 224)` 一致。

## Alternatives Considered

**三態能力宣告**（`unsupported` / `supported(N)` / `supportedUnknownLimit`）。原始 issue 這樣提，但**第三態目前沒有任何 instance**——兩個 whisper backend 上限相同。加一個沒人用的 case，等於要求 6 個 conformer 與所有未來作者處理一個不存在的情況。日後真出現無法宣告上限的後端再加，屆時有真實 instance 可驗證語意。

**給 protocol requirement 預設實作 `.unsupported`**。改動較小、非破壞性，但新引擎會**預設靜默不支援 context**——正是本變更要消滅的失敗模式（宣稱與實際不符）的變體。不採用：本變更的核心命題就是能力必須被明確宣告。

## Non-Goals

- **不**決定哪個引擎在會議廳音訊上最好。本變更只處理能力宣告的正確性。benchmark 語料代表性另案處理。
- **不**處理 whisper 長 prompt 誘發的重複迴圈。那是獨立缺陷，修好本變更後那條路徑仍需另行處理。
- **不**改變 context.json 的 schema、三層目錄解析、或文件擷取流程。
- **不**調整 `clampedPromptTokens` 之外的 WhisperKit 解碼設定。

## Impact

- Affected specs: `asr-engine`（新增能力宣告要求）、`context-calibration`（預算來源與 explain 誠實性）、`asr-routing`（選型納入 prompt 支援度）
- Affected code:
  - Modified:
    - Sources/BestASRKit/Engines/Engine.swift
    - Sources/BestASRKit/Engines/WhisperKitEngine.swift
    - Sources/BestASRKit/Engines/WhisperCppEngine.swift
    - Sources/BestASRKit/Engines/ParakeetEngine.swift
    - Sources/BestASRKit/Engines/AppleSpeechEngine.swift
    - Sources/BestASRKit/Engines/ChineseFamilyEngine.swift
    - Sources/BestASRKit/Engines/ExternalProcessEngine.swift
    - Sources/BestASRKit/CommandCore.swift
    - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
    - Tests/BestASRKitTests/BackendEngineTests.swift
    - Tests/BestASRKitTests/BenchmarkTests.swift
    - Tests/BestASRKitTests/CLITests.swift
    - Tests/BestASRKitTests/PipelineWiringTests.swift
    - Tests/BestASRKitTests/TestSupport.swift
    - CHANGELOG.md
  - New:
    - Sources/BestASRKit/Engines/PromptCapability.swift
    - Tests/BestASRKitTests/PromptCapabilityTests.swift
    - Tests/BestASRKitTests/EngineCapabilityTests.swift
    - Tests/BestASRKitTests/ContextBudgetTests.swift
  - Removed: (none)

> 本清單於 #164 verify round 1 對齊實作：原先列了 `Context/PromptRenderer.swift`
> 與 `ContextTests.swift`（兩者實際未動——`ContextTests` 全部直接呼叫
> `PromptRenderer.render`，不經 `ContextBundle.rendered`），且漏列全部新檔與
> `BenchmarkRunner.swift`。
