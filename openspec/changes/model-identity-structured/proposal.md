## Summary

把模型身分從 provider-first 的 `BackendID` × 字串位址，改成結構化的 `ModelID{family, size}` × runtime。**不改動任何一把既有的 store key。**

> **本文件於 verify round 5 後重寫。** 先前版本描述的是拆分前的 change——它宣稱移除 `default` 佔位字、正規化 size、移除 legacy 修補與 max-uniquing，這四項在 round 4 之後**全部被還原或刻意保留**，而本文件沒有跟上。artifacts 與程式碼漂移到需要逐筆對照才知道哪句還算數，正是 round 4 與 round 5 的 CRITICAL 反覆出現的溫床，所以這裡改成描述**現況**，不描述曾經的意圖。

## Motivation

模型身分的契約**已經存在於持久化層**——`ModelRow` 的 doc comment 寫著 `Key: model_id = backend|family|size|quant`，`ModelRow.id(backend:family:size:quantization:)` 是既有的 public 建構子，37 筆 model 記錄與 383 筆量測都以此為鍵。缺的不是契約，是一個能當**查找鍵**而非序列化格式的型別。

API 層因此走了另一條路：`ModelGrid.row(backend:modelAddress:)` 的位址文法**隨 backend 而變**——mlx-audio 用 `family/size`，其餘用裸 `size`。這造成四個後果，全部已寫在原始碼註解裡：

- **裸 size 查找有歧義**，註解自承「canary 1b shadows mms 1b — **first row wins**」（會靜默回答錯誤的列）
- **size 名稱跨 family 碰撞**，`ModelRegistry.memoryEstimates` 以 `uniquingKeysWith: max` 收斂。實測後果：`sensevoice small` 實需 1.5 GB，被當成 2.5 GB（whisperkit small 的值），在記憶體受限機器上會**排除跑得動的候選**
- **同模型跨 runtime 不可辨識**：`whisper large-v3-turbo` 同時存在於 whisperkit / whisper.cpp / mlx-audio，型別上是三個無關的東西
- **`StoreProjection` 必須丟棄 family** 才能把 store 的四段身分降級成 API 的位址

`accuracyRank(of:)` 也受同一根因影響：它以 `supportedModels`（whisper 尺寸清單）為鍵，**所有非 whisper 模型一律回 -1**，cold-start router 的排序對 parakeet / paraformer / sensevoice / 15 個 mlx family 全部失效。

## Proposed Solution

**1. 引入 `ModelID{family, size}`**，與 runtime（原 `BackendID`）構成身分。`ModelRow` 改為持有 `ModelID` 與 `Quantization`，取代四個鬆散字串。對機序列化沿用 store 現行的 `backend|family|size|quantization`，一個 byte 不改。

**2. 查找改以身分為鍵。** 移除 `modelAddress` 的雙文法與裸 size fallback。使用者輸入的字串另由 `ModelGrid.identity(backend:matching:)` 解析：命中零個或多於一個模型時回 `nil`，由呼叫端拒絕，而非代為挑一個。

**3. `Quantization` 成為封閉列舉**（不適用 / 具名值 / 延後決定並註明由誰決定 / 未知），取代 `String`。**這是型別層的改動；每一列實際帶哪個值不在本 change 內**——見 Non-Goals。

**4. 記憶體估計與 router 排序鍵改以 `ModelID` 為鍵**，讓 `sensevoice small` 拿到自己的 1.5 GB，讓非 whisper family 不再一律 rank −1。

**5. 對人渲染** `family size (runtime)`，CLI 與 MCP 一併直接改，不做 alias 層。

## Non-Goals

以下五項在 verify round 4 之後移出本 change，統一由 **issue #187** 承接。它們互相耦合：任何一項單獨落地都會壞掉，理由記在 #187。

- **catalog re-key**——把每一列的 quantization 指派為真值、把 `mlx-audio parakeet` 的 size 由 `0.6b` 正規化為 `0.6b-v3`。兩者都會旋轉 `model_id`（37 把裡的 19 把），而 383 筆量測中有 **344 筆（89%）** 仍指向舊拼法
- **從身分移除 `default` 佔位字**——與 re-key 不可分離。使用者明確要求過這件事；本 change **沒有做到**
- **`Quantization.isComplete` 拒絕該佔位字**——實測：在 19 列仍拼它的情況下拒絕，會讓 `enumerateCandidates` 回傳**空清單**（whisperkit 全部 6 列被排除）
- **Router 排除身分不完整的候選**——照做會讓 89% 的量測退出排序，本機幾乎每個 measured recommendation 退回 cold-start prior
- **383 筆歷史量測的重新編碼**——上述四項的前提

另外不在本 change 內：

- **納入新模型**——見 issue #185（8 筆已 pin sha 的候選）與 #123（parakeet-unified 新 backend）
- **多因子比較的量測語意**——見 issue #184，blocked by 本 change
- **收攏 `fluid-*` 三個 case 成單一 runtime**——技術上可行（`ChineseFamilyEngine` 已以 instance 屬性接 `BackendID`），但 engine 註冊與 availability probe 需重整，與身分結構正交

## Alternatives Considered

**只統一位址文法、維持 String**（discuss 的方案 B）：改動最小，同樣消滅裸 size 歧義與雙文法。否決理由——身分仍是靠約定維護的字串，而本專案剛在 PR #142 花了 26 輪修「文法隱含的字串解析」缺陷；讓編譯器承擔比讓約定承擔可靠。

**在本 change 內同時 re-key 並加投影層等價**（round 4 的選項 1）：把新舊拼法在投影層收斂成同一候選。否決——等於把資料遷移搬進一個明文宣告不做遷移的 change。

**先做重新編碼、本 change 等**（round 4 的選項 2）：順序正確，但型別工作是 #184 / #185 的前置，沒有理由一起等。

**為 CLI / MCP 保留 alias 層**：使用者明確裁定不需要。

## Impact

- Affected specs: `model-grid`、`benchmark-store`、`asr-engine`、`asr-routing`、`cli`、`mcp-surface`
- Affected code:
  - New:
    - `Sources/BestASRKit/Models/ModelID.swift`
    - `Tests/BestASRKitTests/ModelIDTests.swift`
    - `Tests/BestASRKitTests/ModelRowCodecTests.swift`
    - `Tests/BestASRKitTests/IdentityCompletenessTests.swift`
    - `Tests/BestASRKitTests/IdentityValidationTests.swift`
  - Modified:
    - `Sources/BestASRKit/Store/StoreTables.swift`（`ModelRow` 持有 `ModelID` 與 `Quantization`；平坦 JSON 與四段 key 不變）
    - `Sources/BestASRKit/Models/ModelGrid.swift`（移除 `modelAddress` 雙文法與裸 size fallback；新增 `address(for:backend:)` 作為 writer 與 reader 共用的唯一定址規則）
    - `Sources/BestASRKit/Models/ModelRegistry.swift`（記憶體估計與 `accuracyRank` / `nextSmaller` / `profileModels` 改以 `ModelID` 為鍵。**`uniquingKeysWith: max` 保留**——round 4 證實同一身分在兩個精度下是正常情形，移除它會在 `ColdStartPrior.fits()` 的迴圈裡 fatalError）
    - `Sources/BestASRKit/Models/DataModels.swift`（`BenchmarkRecord` 新增 `identity`；`identityComplete` 為導出屬性）
    - `Sources/BestASRKit/Store/StoreProjection.swift`（移除 mlx 三元運算子。**`parts[1] == parts[2]` 的 legacy 修補保留**——store 內仍有 4 筆這種 id，移除會讓它們與同候選的新量測分家）
    - `Sources/BestASRKit/Router/Router.swift`、`Sources/BestASRKit/Router/ColdStartPrior.swift`
    - `Sources/BestASRKit/CommandCore.swift`（對人渲染與結構化 JSON）
    - `Sources/BestASRKit/Benchmark/BenchmarkRunner.swift`
    - `Sources/BestASRKit/Engines/ChineseFamilyEngine.swift`、`Sources/BestASRKit/Engines/ParakeetEngine.swift`（顯式傳 precision，不再委由相依套件預設）
    - `Sources/BestASRKit/Engines/ExternalProcessEngine.swift`
    - `Sources/bestasr/BestASRCommand.swift`、`Sources/BestASRMCPCore/Server.swift`
    - `Tests/BestASRKitTests/ModelGridTests.swift`、`Tests/BestASRKitTests/DataModelTests.swift`、`Tests/BestASRKitTests/CLITests.swift`、`Tests/BestASRKitTests/RouterTests.swift`、`Tests/BestASRKitTests/BenchmarkTests.swift`、`Tests/BestASRKitTests/BenchmarkStoreTests.swift`、`Tests/BestASRKitTests/AppleSpeechEngineTests.swift`
  - Removed: (none)
