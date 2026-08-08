## 1. 先修截斷方向（實作 design 決策 D4：截斷方向與優先序必須一致）

與預算改動分離，確保方向修正可獨立歸因。對應 spec 需求 `Render context into a natural-language prompt with priority and budget` 中「clamp SHALL preserve the highest-priority items」一句。

- [x] 1.1 將 WhisperKit 端的 prompt token clamp 由保留後綴改為保留前綴，使其與渲染的 names → terms → phrases 優先序一致。驗收：新增測試以超過上限的 token 序列為輸入，斷言保留的是序列開頭而非結尾；該測試不得依賴當前預算值（必須直接餵超過 224 的輸入），否則預算仍為 200 時測試會空轉。

## 2. 建立能力宣告（實作 design 決策 D1：能力宣告採二態，而非三態；D2：protocol requirement 不給預設實作）

對應 spec 需求 `Common engine interface`。

- [x] 2.1 依 D1（二態，不含「上限未知」第三態）在引擎模組新增 public 列舉表示 prompt 能力：不支援；支援並帶最大 token 數。驗收：型別可由模組外部取用；列舉恰有兩個 case。
- [x] 2.2 依 D2 在 `Engine` protocol 新增唯讀屬性 `promptCapability` 回傳該列舉，**不提供預設實作**。驗收：此時建置必然失敗，且錯誤訊息精確列出所有尚未宣告的 conformer——這份清單即為 3.1／3.2 的完整性依據。

## 3. 逐一宣告，滿足 `Common engine interface`（依賴 2.2；彼此檔案不重疊）

- [x] 3.1 [P] 兩個 Whisper 家族後端（WhisperKit 與 whisper.cpp）宣告為支援、上限 224。驗收：測試斷言兩者的宣告值皆為支援且上限 224；224 的依據為 `whisper-cli --help` 所載 `--prompt PROMPT (max n_text_ctx/2 tokens)` 與 Whisper 的 `n_text_ctx = 448`。
- [x] 3.2 [P] 四個不消費 prompt 的後端（Parakeet、Apple Speech、Chinese family、外部程序）宣告為不支援。驗收：測試斷言四者皆宣告不支援；並斷言其轉錄路徑不接收已渲染的 prompt（對應 `Common engine interface` 的「declared capability matches what the backend actually does」情境）。
- [x] 3.3 確認建置回復成功且無 conformer 遺漏。驗收：全專案建置通過，2.2 所列的錯誤清單已全數消除。

## 4. 改預算來源與跳過路徑（實作 design 決策 D3：不支援時跳過整段 render，而非渲染後丟棄）

對應 spec 需求 `Render context into a natural-language prompt with priority and budget`。

- [x] 4.1 渲染呼叫點改為向所選引擎取得預算，取代原本依賴全域預設常數的行為。驗收：測試以宣告上限 224 的引擎執行，斷言實際採用的預算為 224 而非 200。
- [x] 4.2 依 D3，所選引擎宣告不支援時整段跳過渲染，不計算截斷。驗收：測試以不支援的引擎搭配非空 context 執行，斷言未產生截斷清單、且渲染未被執行。
- [x] 4.3 將「宣告支援但最大 token 數為 0」導向與不支援相同的路徑，滿足 `Common engine interface` 的零預算情境。驗收：測試斷言此情況不產生任何 prompt（尤其不得產生空字串 prompt 傳給後端）。

## 5. 誠實化輸出與選型

- [x] 5.1 滿足 spec 需求 `Explain discloses context usage`：explain 的 context 區段在引擎不支援時改為明講該後端不支援 context biasing，且不輸出注入計數與截斷清單。驗收：測試斷言不支援情境下的輸出不含注入計數、且含不支援訊息；支援情境的既有輸出不變。
- [x] 5.2 滿足 spec 需求 `Selection accounts for prompt support when context is present`，依 design 決策 D5（routing 在有 context 時納入支援度，但不硬性過濾）：已解析到 context 目錄且選中不支援 prompt 的後端時發出警告，說明所提供的 context 不會影響本次轉錄；不因此排除該後端。驗收：測試涵蓋三種情形——有 context 且選中不支援者（發警告且仍使用該後端）、有 context 且選中支援者（無警告）、無 context（無警告且選型準則不受影響）。

## 6. 收尾驗證

- [x] 6.1 對照 design 的 Implementation Contract 之 Acceptance criteria 逐條確認測試存在且通過。驗收：每一條 criteria 都能指向一個具名測試。
- [x] 6.2 執行全套件測試並確認全綠。驗收：測試指令回傳成功，且失敗數為 0。
- [x] 6.3 於 CHANGELOG 記錄兩項對使用者可見的變化：`Engine` protocol 新增 requirement 屬 breaking change（D2 的取捨）；同一份 context 在 Whisper 後端上的注入量會因預算由 200 提高到 224 而增加。驗收：CHANGELOG 含這兩點，措辭指明後者屬預期改善而非模型行為漂移。
