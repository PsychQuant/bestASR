## Summary

把模型身分從 provider-first 的 `BackendID` × 字串位址，改成結構化的 `ModelID{family, size}` × runtime，並移除身分裡的 `default` 佔位字。**既有的 store 檔案一個 byte 都不改**——舊 key 在讀取時 canonical 化。

> **本文件於 verify round 6 後再次重寫。** 它先後描述過三個不同的 change：原始版本、round 4 拆分後的版本、以及現在的讀時 canonical 化版本。前兩次它都落後於程式碼，而那正是 round 5 與 round 6 CRITICAL 的來源。本次的規矩是：**先改 artifacts 再送審**，不是改完程式碼才回頭補。

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

**3. `Quantization` 成為封閉列舉**（不適用 / 具名值 / 延後決定並註明由誰決定 / 未知），取代 `String`，且**每一列都帶它真正的值**——`default` 從目錄消失。

**4. 記憶體估計與 router 排序鍵改以 `ModelID` 為鍵**，讓 `sensevoice small` 拿到自己的 1.5 GB，讓非 whisper family 不再一律 rank −1。

**5. 對人渲染** `family size (runtime)`，CLI 與 MCP 一併直接改，不做 alias 層。

**6. 身分不提早壓成字串，翻譯放進 engine**（design D8，round 8 後追加）。`BenchmarkCandidate` 持有 `ModelID`、`ASRRecommendation.model` 由 `identity` 導出而非獨立指定；address → runtime 自有名字的翻譯移進每個 engine 載入模型的那一步。前五輪的缺陷都是同一個形狀——某個已知的身分被壓成字串，之後由別處重新解析或忘了解析。

## Non-Goals

round 4 曾把五項移出本 change，理由是它們都被同一個阻礙擋住：「catalog 帶真值會旋轉 19 把 key，而 344 筆量測指向舊的」。round 6 之後證明那個阻礙不成立——**讀時 canonical 化**（design D7）讓舊 key 在讀取時映射到今天的身分，檔案一個 byte 都不改。五項中的四項因此已落地，只剩：

- **383 筆歷史量測的實體重新編碼**（→ #187）。canonical 化讓它不再是任何事情的前提，但把舊拼法真正寫成新拼法仍有價值：可以移除映射表、讓 store 自我描述。純屬清理，不阻擋任何人。

> **原本列在此處的第二項已刪除並實作。** 它寫的是「`Router` 排除身分不完整的候選（→ #187）……canonical 化後 store 內已無 `.unknown` 的量測，所以這條規則現在沒有可觸發的資料」。**實測推翻該理由**：本機 store 的 383 筆量測中有 **44 筆**（四個 mlx-audio key）canonical 化後 quantization 仍是 `unknown`。規則已於任務 3.3 落地。這句被證偽的話是我自己的改動造成的——它在寫下時就沒有量過。

另外不在本 change 內：

- **納入新模型**——見 issue #185（8 筆已 pin sha 的候選）與 #123（parakeet-unified 新 backend）
- **多因子比較的量測語意**——見 issue #184，blocked by 本 change
- **收攏 `fluid-*` 三個 case 成單一 runtime**——技術上可行（`ChineseFamilyEngine` 已以 instance 屬性接 `BackendID`），但 engine 註冊與 availability probe 需重整，與身分結構正交

## Alternatives Considered

**只統一位址文法、維持 String**（discuss 的方案 B）：改動最小，同樣消滅裸 size 歧義與雙文法。否決理由——身分仍是靠約定維護的字串，而本專案剛在 PR #142 花了 26 輪修「文法隱含的字串解析」缺陷；讓編譯器承擔比讓約定承擔可靠。

**在本 change 內同時 re-key 並加投影層等價**（round 4 的選項 1）：**這就是最後採用的方案**（design D7）。round 4 時我把它描述成「等於把資料遷移搬進一個宣告不做遷移的 change」而否決——那個描述是錯的：讀時映射一個 byte 都不寫。這個錯誤估計讓後續三輪走錯方向。

**先做重新編碼、本 change 等**（round 4 的選項 2）：否決——canonical 化之後，重新編碼不再是任何事情的前提。

**拆分：型別先落地、re-key 隨重新編碼**（round 4 的選項 3，round 4–6 實際採用）：否決並已回退。它把「能交付 issue 的部分」延後、「不能交付的部分」留下，round 6 的五個 CRITICAL 有四個是「沒交付」而非「壞掉」。

**為 CLI / MCP 保留 alias 層**：使用者明確裁定不需要。

## Impact

- Affected specs: `model-grid`、`benchmark-store`、`asr-engine`、`asr-routing`、`cli`、`mcp-surface`
- Affected code:
  - New:
    - `Sources/BestASRKit/Models/ModelID.swift`
    - `Tests/BestASRKitTests/EngineSeamTests.swift`（spy engine 與兩條路徑共用的斷言）
    - `Tests/BestASRKitTests/ModelIDTests.swift`
    - `Tests/BestASRKitTests/ModelRowCodecTests.swift`
    - `Tests/BestASRKitTests/IdentityCompletenessTests.swift`
    - `Tests/BestASRKitTests/IdentityValidationTests.swift`
  - Modified:
    - `Sources/BestASRKit/Store/StoreTables.swift`（`ModelRow` 持有 `ModelID` 與 `Quantization`；平坦 JSON 與四段 key 不變）
    - `Sources/BestASRKit/Models/ModelGrid.swift`（移除 `modelAddress` 雙文法與裸 size fallback；`address(for:)` 一律回 `family/size`，**不收 backend**——位址 runtime-independent 是 #183 第三條 EXPECTED；新增 `canonical(...)` 做讀時映射）
    - `Sources/BestASRKit/Models/ModelRegistry.swift`（記憶體估計與 `accuracyRank` / `nextSmaller` / `profileModels` 改以 `ModelID` 為鍵。**`uniquingKeysWith: max` 保留**——round 4 證實同一身分在兩個精度下是正常情形，移除它會在 `ColdStartPrior.fits()` 的迴圈裡 fatalError）
    - `Sources/BestASRKit/Models/DataModels.swift`（`BenchmarkRecord` 新增 `identity`；`identityComplete` 為導出屬性）
    - `Sources/BestASRKit/Store/StoreProjection.swift`（移除 mlx 三元運算子；改為呼叫 `ModelGrid.canonical(...)` 做讀時映射，`family == size` 的 legacy 規則也收進該處）
    - `Sources/BestASRKit/Router/Router.swift`、`Sources/BestASRKit/Router/ColdStartPrior.swift`
    - `Sources/BestASRKit/CommandCore.swift`（對人渲染與結構化 JSON）
    - `Sources/BestASRKit/Benchmark/BenchmarkRunner.swift`
    - `Sources/BestASRKit/Engines/ChineseFamilyEngine.swift`、`Sources/BestASRKit/Engines/ParakeetEngine.swift`（顯式傳 precision，不再委由相依套件預設）
    - `Sources/BestASRKit/Engines/ExternalProcessEngine.swift`
    - `Sources/bestasr/BestASRCommand.swift`、`Sources/BestASRMCPCore/Server.swift`
    - `Tests/BestASRKitTests/ModelGridTests.swift`、`Tests/BestASRKitTests/DataModelTests.swift`、`Tests/BestASRKitTests/CLITests.swift`、`Tests/BestASRKitTests/RouterTests.swift`、`Tests/BestASRKitTests/BenchmarkTests.swift`、`Tests/BestASRKitTests/BenchmarkStoreTests.swift`、`Tests/BestASRKitTests/AppleSpeechEngineTests.swift`
  - Removed: (none)
