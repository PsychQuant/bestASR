## 1. 測試先行（TDD）

- [x] 1.1 更新 Tests/BestASRKitTests/ContextTests.swift 的 `ContextResolutionTests` 既有案例，使工作目錄層改用 `.bestasr/context`：`Working-directory layer wins over the global layer` 建立 `cwd/.bestasr/context`，斷言 `resolveDirectory(flag: nil)` 回傳該路徑。行為：Resolve the context directory by three-layer precedence 的 cwd 層對齊新路徑。驗證：`swift test --filter ContextResolutionTests` 該案由紅轉綠。
- [x] 1.2 在 Tests/BestASRKitTests/ContextTests.swift 新增 negative 案例「Legacy cwd directory is no longer resolved」：建立 `cwd/bestasr-context`、無 `.bestasr/context`、無 global，斷言 `resolveDirectory(flag: nil)` 回傳 nil。行為：舊 `bestasr-context/` 即使存在也不再被解析（breaking）。驗證：`swift test --filter ContextResolutionTests` 新案存在且綠。

## 2. 實作

- [x] 2.1 將 Sources/BestASRKit/Context/ContextLoader.swift 的 `cwdDirectoryName` 由 `"bestasr-context"` 改為 `".bestasr/context"`，並更新三層解析註解為 `--context-dir > ./.bestasr/context/ > ~/.bestasr/context/`。行為：`resolveDirectory` 的 cwd 層解析到 `<cwd>/.bestasr/context`。驗證：第 1 節測試全綠。
- [x] 2.2 驗證 `cwd.appendingPathComponent(cwdDirectoryName, isDirectory: true)` 對含 `/` 的 `.bestasr/context` 正確產生 `<cwd>/.bestasr/context`（未被當成單一 component 編碼）；若行為不符，改為逐層 append（先 `.bestasr` 再 `context`）。行為：cwd candidate 的 URL path 結尾為 `/.bestasr/context`。驗證：1.1 案的 `#expect(resolved?.path == cwdCtx.path)` 通過。

## 3. 對外文件與遷移說明

- [x] 3.1 [P] 更新 README.md 的 context 目錄說明與範例（三層解析描述、目錄範例、`voices/` 範例段落）改用 `.bestasr/context`。行為：README 對外描述與新解析行為一致。驗證：README 內不再出現作為現行用法的 `bestasr-context`（CHANGELOG 歷史條目除外）。
- [x] 3.2 [P] 更新 plugins/bestasr/skills/context-ingest/SKILL.md 的預設工作目錄層路徑為 `.bestasr/context`。行為：context-ingest skill 指引使用者建立/尋找的 cwd 層路徑正確。驗證：檔內 cwd 層描述為 `.bestasr/context`。
- [x] 3.3 [P] 更新 plugins/bestasr/skills/transcript/SKILL.md 的 context 解析描述與 `--context-dir` 範例為 `.bestasr/context`。行為：transcript skill 的 context 解析說明與範例一致。驗證：檔內範例路徑為 `.bestasr/context`。
- [x] 3.4 [P] 在 CHANGELOG.md 新增一則 breaking-change 條目，載明工作目錄層 context 目錄改名，並附手動遷移動作（將既有 bestasr-context 目錄重新命名為 .bestasr/context）。行為：使用者可從 CHANGELOG 得知 breaking 與遷移方式。驗證：CHANGELOG 有對應條目含遷移說明。

## 4. 整合驗證

- [x] 4.1 執行 `swift test` 全套綠，確認 Resolve the context directory by three-layer precedence 的所有 scenario（含新 negative case）通過，且無其他測試因改名而回歸。驗證：`swift test` exit 0。
