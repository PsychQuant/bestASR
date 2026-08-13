## Context

模型身分目前有兩套並行的表達，而**只有持久化層那套是對的**。

`ModelRow`（`Sources/BestASRKit/Store/StoreTables.swift`）的 doc comment 寫著 `Key: model_id = backend|family|size|quant`，並提供 public 建構子 `ModelRow.id(backend:family:size:quantization:)`。37 筆 model 記錄與 383 筆量測都以此四段字串為鍵，文法統一、對每個 backend 一致、family 是一等公民。

API 層走了另一條路。`ModelGrid.row(backend:modelAddress:)` 接受一個**文法隨 backend 而變**的字串：mlx-audio 用 `family/size`，其餘用裸 `size`。`StoreProjection` 因此必須把 store 的四段身分**降級**成 API 位址，對非 mlx 的列直接丟棄 family。同一份檔案裡還留著一段 legacy 修補（`family == size` 的舊記錄改寫成 `whisper`），註記來自 #14——**store 早就做過一次「從無 family 搬到四段身分」的遷移，API 層沒有跟上**。

四個既有 patch（#20 / #35 / #50 / #65）都是這個落差的下游，`Models/` 底下共 12 處引用。

約束：

- 對機序列化**不能改**。337 筆記錄（37 model + 300 measurement 外鍵）以四段字串為鍵，本 change 不做資料遷移
- `WeightVerifier` 對 grid 列有 pinned revision + digest 要求
- 使用者已裁定：CLI 與 MCP 一併直接改，不做 alias
- `.spectra.yaml` locale 為 tw；spec delta 依規定仍以英文撰寫

## Goals / Non-Goals

**Goals:**

- 模型身分成為型別（`ModelID`），可當查找鍵、可比較、可雜湊
- 同一模型在不同 runtime 下**可被辨識為同一模型**（`whisper large-v3-turbo` 於 whisperkit / whisper.cpp / mlx-audio）
- 身分中不再出現 `default` 佔位字；無法確定的情況以型別明示，並使該列無法進入比較
- 收攏四個既有轉譯點為一個
- 對機字串零改動，對人字串改為 `family size (runtime)`

**Non-Goals:**

- 342 筆歷史量測的重新編碼（另立 change；使用者已裁定採「重新編碼能映射的部分」，un-mappable 的處置見 Decision 5）
- 納入新模型（#185 / #123）
- 多因子比較的量測語意（#184）
- 收攏 `fluid-*` 三個 `BackendID` case 成單一 runtime——與身分結構正交
- 為 CLI / MCP 保留 alias（使用者明確裁定不需要）

## Decisions

### D1：`ModelID` 只含 `family` + `size`，不含 quantization 與 runtime

`ModelID` 是「哪一個模型」；quantization 是同一模型的變體，runtime 是宿主。三者是**同位因子**而非組成部分。

**為什麼不把 quantization 併進來**：併進去之後「同模型不同量化」在型別上成為兩個不同模型，`whisper large-v3-turbo` 的 4bit 與 8bit 就無法比較——那正是 #184 要做的事，會被本 change 提前堵死。

**替代方案**：`ModelID{family, size, quantization}`（三段）。否決，理由如上。

### D2：對機序列化沿用四段字串，由 `ModelID` 產出

序列化形式 `runtime|family|size|quantization` 與 store 現行完全一致，因此 337 筆既有記錄的鍵**不需要任何遷移**。`ModelRow.id(...)` 保留為相容入口，內部改由 `ModelID` 組出。

**替代方案**：改用 JSON 物件或新分隔符。否決——會迫使本 change 承擔資料遷移，而遷移已明確劃為另一個 change。

### D3：`size` 正規化是前提，不是附帶清理

pinned repo 證明兩筆 parakeet 指向**同一個模型版本**：

- `fluid-parakeet` size `0.6b-v3` → `FluidInference/parakeet-tdt-0.6b-v3-coreml`
- `mlx-audio` size `0.6b` → `mlx-community/parakeet-tdt-0.6b-v3`

若不正規化，`ModelID("parakeet", "0.6b")` ≠ `ModelID("parakeet", "0.6b-v3")`，兩個 runtime 仍然關聯不起來，本 change 的主要目的失效。

正規化規則：**size 取自 pinned upstream artifact 所宣告的版本**，而非目錄作者的簡寫。有 `hfRepo` 的列以 repo id 為準；無 repo 的列（whisperkit / apple-speech）維持現值，並在 spec 記錄該來源為 runtime 自管。

**替代方案**：加一層 alias 對照表把 `0.6b` 映到 `0.6b-v3`。否決——那是把約定再疊一層，且對照表無人維護時會與 pin 漂移。

### D4：quantization 成為封閉列舉，四個 case

```
notApplicable          // 該 runtime 無量化維度（apple-speech）
named(String)          // 真值：q5_1 / q8_0 / 4bit / q8 …
deferred(Deferrer)     // 有人會決定，但不是我們。Deferrer = .runtime | .dependency
unknown                // 沒人知道
```

`deferred` 與 `unknown` 必須分開，因為性質不同：`deferred(.dependency)` 是**會隨相依版本無聲漂移**的值（`ChineseFamilyEngine` 呼叫 `ParaformerManager.load()` 未傳 precision，而 FluidAudio 提供 `ParakeetEncoderPrecision{int8, int4}`），`unknown` 只是資料缺口。把兩者都寫成 `default` 就看不出哪一個會漂移。

`unknown` 的語意是**使該列不得進入比較**——不完整的身分不該被當成可比較的量測對象。

**替代方案**：`String?`，nil 表示不適用。否決——無法區分上述四種，而稽核顯示現況正是七種情況壓成一個字（`docs/model-identity-audit.csv`）。

### D5：`deferred(.dependency)` 在本 change 內就地消除

`ChineseFamilyEngine` 改為**顯式傳入 precision**，不再委由 FluidAudio 預設。三列 `fluid-*` 因此從 `deferred` 變成 `named`。

這是本 change 唯一觸及 engine 行為的改動，理由是它同時修掉一個實質缺陷：目前同一列在 FluidAudio 0.15.4 與 0.15.5 下可能是不同量化而身分完全相同——PR #142 正在為那個版本 bump 建立證據，卻無法偵測這一項。

whisperkit 的 6 列維持 `deferred(.runtime)`：上游 `argmaxinc/whisperkit-coreml` publish 27 個具名 variant，`large-v3-turbo` 對應至少 4 個（差在 checkpoint 日期 v20240930 與壓縮大小 954MB / 632MB）。查明 WhisperKit 實際選用哪一個需要讀它的下載邏輯，屬於獨立工作，本 change 只保證該狀態**被明確標記為延後**而非偽裝成已知。

### D6：`accuracyRank` / `nextSmaller` / `profileModels` 改以 `ModelID` 為鍵

三者目前以 `supportedModels`（whisper 尺寸清單）為鍵，非 whisper 模型的 `accuracyRank` 一律回 -1，cold-start router 排序對 parakeet / paraformer / sensevoice / 15 個 mlx family 全部失效。身分改了而這三個不改，等於修好型別卻沒修行為。

## Implementation Contract

**Behavior（可觀察的結果）**

1. `bestasr list-models` 的輸出對每個模型顯示 `family size (runtime)`，且**不再出現 `default` 字樣**；量化未定的列顯示其延後來源（如 `quantization deferred to runtime`）
2. `bestasr recommend` 對非 whisper 家族的模型給出與 whisper 家族一致的排序行為（不再因 `accuracyRank == -1` 而墊底）
3. `ModelRegistry.requirements(for:)` 對 `sensevoice small` 回 1.5 GB（今日回 2.5 GB，即 whisperkit small 的值）
4. MCP `list_models` / `list_backends` 的輸出同步改為新形式

**Interface / data shape**

- 新型別 `ModelID`：`family: String`、`size: String`，`Hashable`、`Codable`、`Sendable`
- `ModelID` **只有一個建構子且為 failable**（`init?(family:size:)`）。無不檢查的入口——`BestASRKit` 是單一 module，`internal` 的逃生口保護不了任何東西，最可能走捷徑的呼叫者就在 module 內。持有編譯期字面值的呼叫端（catalog）自行 unwrap 一次並大聲失敗
- `ModelID` 與 `Quantization(named:)` 共用同一組**語法**拒絕規則：空字串、純空白、**前後帶空白**（`"whisper "` 與 `"whisper"` 會變成同一模型的兩個身分，正是本 change 要終結的缺陷類）
- **`default` 的規則刻意不放在 `ModelID` 建構子**。它是目錄列**內容**的缺陷，不是元件語法的缺陷：37 筆記錄中有 2 筆（`mega-asr`、`qwen3-forcedaligner`）的 size 就是這個字串，而任務 4.1 要求 `StoreProjection` 直接由那四段建構 `ModelID`。若在型別層拒絕，這些歷史記錄將**讀不進來**，與 benchmark-store 的 "Incomplete records remain readable" 直接衝突。「任何**列**都不得帶它」由目錄層的測試（任務 2.4）執行。`Quantization(named:)` 仍拒絕它——那裡它不是內容問題，而是封閉列舉中不存在的 case
- 新型別 `Quantization`：四 case 封閉列舉（見 D4），`Codable` 序列化為既有字串值（`named` 直出其值；其餘三者各有保留字）。`init(serialised:)` **仍會**把舊值 `"default"` 讀成 `.named("default")`——不重新詮釋，讓錯的記錄讀起來仍然是錯的，migration 才找得到
- `ModelRow` 持有 `ModelID` 與 `Quantization`，其序列化 `model_id` 字串維持 `runtime|family|size|quantization` 四段，**與現行 37 筆記錄逐字相容**
- `ModelGrid.row(backend:modelAddress:)` 移除，改為以 `ModelID` + runtime 查找的介面

**Failure modes**

- 身分不完整（`Quantization.unknown` 或 `size` 缺失）的列：`ModelGrid` 仍收錄以供查閱，但 `Router` 與 benchmark 候選列舉**排除**它，並在 `notes` 出現一則具名說明。**不得靜默略過**
- 舊格式 `modelAddress` 字串傳入已移除的介面：編譯期失敗（此為刻意——使用者裁定不做 alias）
- `ModelRow.id` 的四段字串解析遇到非四段輸入：回傳 nil 而非崩潰，呼叫端須處理

**Acceptance criteria**

- `ModelRegistryTests`：新增一則主張 `requirements(for: ModelID("sensevoice","small"))` 回 1.5 GB 且不等於 `ModelID("whisper","small")` 的值；`memoryEstimates` 中不再存在 `uniquingKeysWith: max`
- `ModelGridTests`：新增一則主張 `ModelID("parakeet","0.6b-v3")` 在 fluid 與 mlx 兩個 runtime 下**是同一個 `ModelID`**（size 正規化生效）；並主張 `Quantization` 為 `.unknown` 的列**恰好**是 8 列未 bundle 的 mlx-audio reference row（封閉列舉，見 tasks 2.4）。（原條文寫「任一 grid 列的 `Quantization` 不為 `.unknown`」，與 tasks 2.4 明文指派 `unknown` 給部分列直接矛盾——此處以 tasks 為準修正）
- 全域檢查：`Sources/` 中不再有任何列**以** `default` 作為 quantization 或 size 的值。以 grep 驗證，並且**恰好只有一個允許的例外**：`ModelID.removedPlaceholder` 這個具名常數（它的存在正是為了拒絕該字面值，且讓「主張其不存在的測試」與「拒絕它的建構子」不會對拼法各說各話）。此為封閉列舉，**不得依性質相似再加第二個例外**
- `StoreProjection` 中不再存在針對特定 backend 的分支（mlx 三元運算子與 `parts[1] == parts[2]` legacy 修補皆移除）
- 既有 37 筆 `models.jsonl` 記錄以新程式讀入後，其 `model_id` 序列化結果與檔案中的字串**逐字相同**
- 全套測試綠燈（本分支基線實測 493 筆 / 98 suites，於 `idd/183-model-identity-audit` 起點量得；先前寫的 453 是 PR #142 分支的數字）

**Scope boundaries**

- **In scope**：型別、目錄查找、記憶體估計、router 排序鍵、CLI 與 MCP 對外字串、`ChineseFamilyEngine` 的 precision 顯式化、對應測試、六份 spec delta
- **Out of scope**：歷史量測記錄的重新編碼、新模型納入、多因子比較語意、`fluid-*` 三 case 的收攏、WhisperKit 實際 variant 的查明
