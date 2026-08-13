## Summary

把模型身分從 provider-first 的 `BackendID` × 字串位址，改成結構化的 `ModelID{family, size}` × runtime，並移除身分裡的 `default` 佔位字。

## Motivation

模型身分的契約**已經存在於持久化層**——`ModelRow` 的 doc comment 寫著 `Key: model_id = backend|family|size|quant`，`ModelRow.id(backend:family:size:quantization:)` 是既有的 public 建構子，37 筆 model 記錄與 383 筆量測都以此為鍵。缺的不是契約，是一個能當**查找鍵**而非序列化格式的型別。

API 層因此走了另一條路：`ModelGrid.row(backend:modelAddress:)` 的位址文法**隨 backend 而變**——mlx-audio 用 `family/size`，其餘用裸 `size`。這造成四個後果，全部已寫在原始碼註解裡：

- **裸 size 查找有歧義**，註解自承「canary 1b shadows mms 1b — **first row wins**」（會靜默回答錯誤的列）
- **size 名稱跨 family 碰撞**，`ModelRegistry.memoryEstimates` 以 `uniquingKeysWith: max` 收斂。實測後果：`sensevoice small` 實需 1.5 GB，被當成 2.5 GB（whisperkit small 的值），在記憶體受限機器上會**排除跑得動的候選**
- **同模型跨 runtime 不可辨識**：`whisper large-v3-turbo` 同時存在於 whisperkit / whisper.cpp / mlx-audio，型別上是三個無關的東西
- **`StoreProjection` 必須丟棄 family** 才能把 store 的四段身分降級成 API 的位址

`accuracyRank(of:)` 也受同一根因影響：它以 `supportedModels`（whisper 尺寸清單）為鍵，**所有非 whisper 模型一律回 -1**，cold-start router 的排序對 parakeet / paraformer / sensevoice / 15 個 mlx family 全部失效。

同時，19/37 的身分帶 `default`，而 `default` 目前代表七件不同的事（稽核表在 `docs/model-identity-audit.csv`）。最嚴重的一類是 `dependency-decides`：`ChineseFamilyEngine` 呼叫 `ParaformerManager.load()` **未傳 precision**，而 FluidAudio 提供 `ParakeetEncoderPrecision{int8, int4}`——量化由相依套件決定，**版本一 bump 值就可能改變而身分不動**。

## Proposed Solution

**1. 引入 `ModelID{family, size}`**，與 runtime（原 `BackendID`）構成身分。`ModelRow` 改為持有 `ModelID`，取代四個鬆散字串。對機序列化沿用 store 現行的 `backend|family|size|quantization`，一個 byte 不改。

**2. 正規化 `size`。** pinned repo 證明兩筆 parakeet 是**同一個模型版本**（`FluidInference/parakeet-tdt-0.6b-v3-coreml` 與 `mlx-community/parakeet-tdt-0.6b-v3`），而目錄一邊寫 `0.6b-v3`、一邊寫 `0.6b`。不正規化，`ModelID` 相等性對它們無效，本 change 的主要目的達不成。

**3. 量化改為封閉列舉**，取代 `default` 字串：不適用 / 具名值 / 延後決定（並註明由 runtime 或相依套件決定）/ 未知。`unknown` 使該列**無法進入比較**，而非塞一個假值。

**4. 對人渲染** `family size (runtime)`，例如 `whisper large-v3-turbo (whisperkit)`。

**5. CLI 與 MCP 一併直接改**，不做 alias 層。

## Non-Goals

- **342 筆歷史量測的重新編碼**——另立 change（本 change 只讓新記錄的身分完整；舊記錄的處置是獨立的風險與失敗模式）
- **納入新模型**——見 issue #185（8 筆已 pin sha 的候選）與 #123（parakeet-unified 新 backend）
- **多因子比較的量測語意**——見 issue #184，blocked by 本 change
- **收攏 `fluid-*` 三個 case 成單一 runtime**——技術上可行（`ChineseFamilyEngine` 已以 instance 屬性接 `BackendID`），但 engine 註冊與 availability probe 需重整，與身分結構正交，不放本 change

## Alternatives Considered

**只統一位址文法、維持 String**（discuss 的方案 B）：改動最小，同樣消滅裸 size 歧義與雙文法。否決理由——身分仍是靠約定維護的字串，而本專案剛在 PR #142 花了 26 輪修「文法隱含的字串解析」缺陷；讓編譯器承擔比讓約定承擔可靠。

**保留 `default` 只做位址正規化**：否決。`default` 遮蔽的是**會隨相依版本無聲漂移**的值（見 Motivation 的 `dependency-decides`），位址正規化不觸及它。

**為 CLI / MCP 保留 alias 層**：使用者明確裁定不需要（CLI 為個人使用；MCP 雖為已發佈 plugin 契約，使用者選擇直接改）。

## Impact

- Affected specs: `model-grid`、`benchmark-store`、`asr-engine`、`asr-routing`、`cli`、`mcp-surface`
- Affected code:
  - Modified:
    - `Sources/BestASRKit/Store/StoreTables.swift`（`ModelRow` 持有 `ModelID`；`ModelRow.id` 改由型別產出）
    - `Sources/BestASRKit/Models/ModelGrid.swift`（移除 `modelAddress` 雙文法與裸 size fallback）
    - `Sources/BestASRKit/Models/ModelRegistry.swift`（記憶體估計改以 `ModelID` 為鍵，移除 max-uniquing；`accuracyRank` / `nextSmaller` / `profileModels` 改鍵）
    - `Sources/BestASRKit/Models/DataModels.swift`（`BackendID` 語意收斂為 runtime）
    - `Sources/BestASRKit/Store/StoreProjection.swift`（移除 mlx 特例與 legacy 修補）
    - `Sources/BestASRKit/Store/BenchmarkStore.swift`
    - `Sources/BestASRKit/Router/Router.swift`、`Sources/BestASRKit/Router/ColdStartPrior.swift`
    - `Sources/BestASRKit/CommandCore.swift`（對人渲染）
    - `Sources/BestASRKit/Benchmark/BenchmarkRunner.swift`
    - `Sources/BestASRKit/Engines/Engine.swift`
    - `Sources/BestASRKit/Engines/ChineseFamilyEngine.swift`（顯式傳 precision，不再委由相依套件預設）
    - `Sources/bestasr/BestASRCommand.swift`（CLI 對外字串）
    - `Sources/BestASRMCPCore/Server.swift`（`list_backends` / `list_models` 輸出）
    - `Tests/BestASRKitTests/ModelRegistryTests.swift`、`Tests/BestASRKitTests/ModelGridTests.swift`
  - New:
    - `Sources/BestASRKit/Models/ModelID.swift`
  - Removed: (none)
