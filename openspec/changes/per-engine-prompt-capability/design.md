## Context

context biasing 目前的資料流是：載入 context 目錄 → `PromptRenderer.render` 依 names → terms → phrases 優先序渲染成逗號分隔詞表、受約 200 token 預算截斷 → 交給引擎。

問題在最後一步：`Engine` 是 public protocol，目前有三個 requirement（識別碼、可用性偵測、原始轉錄），**沒有任何地方描述該引擎是否消費 prompt**。實際上 6 個 conformer 只有兩個 whisper backend 會讀，其餘 4 個把它丟掉。渲染與截斷卻對全部引擎照跑，CLI 的 explain 也對全部引擎印出注入計數。

約束：

- `Engine` 是 **public** protocol，契約同時對 repo 外與未來的引擎作者生效。增加 requirement 是 source-breaking。
- 兩個 whisper backend 的上限已實證收斂為 **224**（`whisper-cli --help` 明載 `--prompt PROMPT (max n_text_ctx/2 tokens)`，Whisper `n_text_ctx = 448`；WhisperKit 端的 clamp 亦為 224）。
- 現行 200 的註解本身即寫明「為 Whisper 而調」——設計沒錯，錯在被無條件套用到不是 Whisper 的東西。
- `PromptRenderer.render` 全 codebase 僅一個呼叫點，位於命令核心組裝 context bundle 之處，故管線改動面小；成本集中在 protocol 與 conformer。

## Goals / Non-Goals

**Goals:**

- 讓「此引擎是否支援 prompt、上限多少」成為引擎自己宣告的、型別層可檢查的事實。
- 預算由所選引擎決定，而非全域常數。
- 不支援 prompt 時**不執行** render、**不宣稱**注入——消滅「宣稱與實際不符」。
- 選型在有 context 時把 prompt 支援度納入考量。

**Non-Goals:**

- 不評比哪個引擎在特定音訊類型上較佳，也不調整 benchmark 語料。
- 不處理長 prompt 誘發的解碼重複問題。
- 不更動 context.json schema、三層目錄解析、文件擷取。
- 不引入 prompt 內容的語意最佳化（例如依音訊自動挑詞）。

## Decisions

### D1：能力宣告採二態，而非三態

採 `unsupported` 與 `supported(maxTokens:)` 兩態。

原始 issue 提議三態，第三態為「支援但上限未知，交由後端自行截斷」。**否決理由：該態目前沒有任何 instance。** 兩個 whisper backend 上限相同且已知。為不存在的情況新增 case，會要求 6 個 conformer 與所有未來作者處理一個無法驗證語意的分支。日後若真出現無法宣告上限的後端，屆時有真實 instance 可據以定義行為，再擴充。

代價：未來新增第三態是 source-breaking 的第二次。接受——比現在憑想像定義語意好。

### D2：protocol requirement 不給預設實作

不提供 `extension Engine { var promptCapability: ... { .unsupported } }`。

給預設會讓新引擎**預設靜默不支援 context**，這正是本變更要消滅的失敗模式（系統宣稱與實際不符）的變體：作者沒想過這件事，系統替他選了一個看起來安全的答案。本變更的核心命題是「能力必須被明確宣告」，給預設與初衷相反。

代價：6 個既有 conformer 全部要改，且對 repo 外的實作是 source-breaking。這是**明知的**取捨——一次有界的成本，換取往後每個新引擎都被迫回答這個問題。

### D3：不支援時跳過整段 render，而非渲染後丟棄

引擎宣告 `unsupported` 時，命令核心不呼叫 render。理由有二：一是截斷計算與 `exhausted` 判定對該引擎完全無意義，跑了只是浪費並產生誤導性的統計；二是 explain 的輸出必須據此改變措辭，兩者需在同一個判斷點決定。

### D4：截斷方向與優先序必須一致

渲染的優先序是 names → terms → phrases（最重要在前），而 WhisperKit 端的 token clamp 取的是**後綴**，砍掉的正是最前面的人名。目前預算 200 < 上限 224 撞不到，故無可觀測差異；但預算一旦依引擎提高到 224，兩個機制的方向相反會產生實際錯誤。本變更把 clamp 改為取前綴，**必須在提高預算之前完成**，否則兩個變因混在一起無法歸因。

### D5：routing 在有 context 時納入支援度，但不硬性過濾

`recommend` 偵測到 context 目錄存在時，把 prompt 支援度納入選型考量；選中 `unsupported` 引擎時發出警告。

不採「硬性排除不支援的引擎」：WER 與 context 支援何者較重要並未量測，硬排可能把明顯較準的引擎擋掉。警告把判斷交還使用者，且不宣稱系統知道它其實不知道的事。

## Implementation Contract

**Behavior（使用者可觀察到的變化）**

- 以支援 prompt 的後端轉錄且存在 context 時：行為與現況相同，惟預算改由該後端宣告（兩個 whisper backend 為 224，高於現行 200，故可注入的項目數會增加）。
- 以不支援 prompt 的後端轉錄且存在 context 時：**不再**出現注入計數與截斷清單；改為一則明確訊息，指出該後端不支援 context biasing。
- 存在 context 目錄而選型選中不支援的後端時：發出警告，指出 context 將不生效。

**Interface / data shape**

- `Engine` protocol 新增一個唯讀屬性，回傳 prompt 能力，型別為二態列舉：不支援；支援並帶一個非負的最大 token 數。
- 該列舉為 public，與 `Engine` 同一模組公開。
- `PromptRenderer` 的渲染入口接受 token 預算參數（既有），呼叫端改為傳入所選引擎宣告的上限；`defaultTokenBudget` 不再作為隱含全域預設被單一呼叫點依賴。
- explain 的 context 區段在不支援時輸出「不支援」訊息，而非注入／截斷計數。

**Failure modes**

- 引擎宣告 `supported(maxTokens:)` 但 `maxTokens` 為 0：視同不支援，走同一條「不執行 render」路徑，不得產生空 prompt 傳給後端。
- context 目錄不存在：維持現況零影響，不因本變更產生任何新輸出。
- 外部程序引擎（協定型後端）宣告 `unsupported`：其協定目前無 prompt 欄位，不得因本變更在協定上新增欄位。

**Acceptance criteria**

- 對每個 conformer 存在測試斷言其宣告值，且宣告與該引擎是否真的把 prompt 傳給後端一致。
- 存在測試：以 `unsupported` 引擎搭配非空 context 執行，斷言 explain 輸出不含注入計數、且渲染未被執行。
- 存在測試：以 `supported(224)` 引擎執行，斷言實際採用的預算為 224 而非 200。
- 存在測試：截斷方向與渲染優先序一致——超出上限時被丟棄的是低優先項，而非最前面的人名。
- 全套件測試通過。

**Scope boundaries**

- 在範圍內：`Engine` protocol 與其 6 個 conformer、prompt 渲染的預算來源、explain 的 context 區段措辭、選型對 context 存在的反應、WhisperKit 端 clamp 的方向。
- 在範圍外：context.json schema、目錄解析、文件擷取、benchmark 語料與排名、解碼參數（除 clamp 方向外）、外部引擎協定的欄位定義。

## Risks / Trade-offs

- **改 public protocol 是廣播式改動，對 repo 外實作 source-breaking** → 這是 D2 的明知取捨。以 release note 標示 breaking，並在 6 個 in-repo conformer 一次改完，讓編譯器成為完整性檢查。
- **預算由 200 提高到 224，改變既有使用者的實際 prompt 內容** → 同一份 context 在同一後端上會注入更多項目，逐字稿可能改變。屬預期改善，但應在 release note 標明「context 注入量會增加」，避免被誤認為模型行為漂移。
- **D4 的 clamp 方向改動在現行預算下無可觀測差異，容易被誤判為無效改動而被省略** → 必須在提高預算之前落地並附測試，測試需以超過上限的輸入直接驗證方向，而非依賴當前預算值。
- **D5 的警告可能被使用者忽略，效果有限** → 接受。硬性過濾需要「WER 與 context 支援孰重」的量測依據，目前沒有；寧可警告而不假裝知道。
- **`maxTokens` 為 0 的宣告是型別上合法但語意可疑的狀態** → 於 Failure modes 明訂等同不支援，並以測試鎖住，避免產生空 prompt。

## Migration Plan

1. 先落地 D4（clamp 方向），與預算改動分離，確保方向修正可獨立歸因。
2. 新增能力列舉與 protocol requirement；此時編譯失敗會精確列出所有未宣告的 conformer。
3. 逐一為 6 個 conformer 補宣告：兩個 whisper backend 為支援並帶上限 224，其餘 4 個為不支援。
4. 改渲染呼叫點：由所選引擎取得預算；不支援時跳過 render。
5. 改 explain 措辭與選型警告。
6. 補齊 Acceptance criteria 所列測試，跑全套件。

無資料遷移、無持久化狀態變更，故不需回填或相容層。回退方式為整體回退本變更。
