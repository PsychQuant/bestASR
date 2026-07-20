## Why

bestASR 的 context 目錄採三層解析（先看 --context-dir，再看工作目錄層，最後看 home 層）。home 層已使用隱藏目錄形式 ~/.bestasr/context/，但工作目錄層卻是明碼、連字號的 ./bestasr-context/，兩層命名不對稱。工作目錄層的明碼目錄會出現在專案檔案列表中，也與 .bestasr/ 的 dotfolder 慣例不一致。本次將工作目錄層改為 ./.bestasr/context/，使兩層對稱，讓 .bestasr/ 成為專案內外一致的隱藏設定目錄。

## What Changes

- **BREAKING**：工作目錄層 context 目錄從 ./bestasr-context/ 改為 ./.bestasr/context/。三層解析順序變為：--context-dir 優先，其次 ./.bestasr/context/，最後 ~/.bestasr/context/。
- 不保留 ./bestasr-context/ 作為 fallback（硬切換）。既有目錄需由使用者手動重新命名為新路徑，遷移動作記入 CHANGELOG。
- 更新 ContextLoader 的 cwdDirectoryName 常數值與三層解析註解。
- 更新測試：修改既有解析測試的路徑，並新增一個 negative 測試，確認舊的 ./bestasr-context/ 目錄即使存在也不再被解析，以鎖住 breaking 行為。
- 更新對外文件：context-ingest 與 transcript 兩個 skill 的說明、README（含 voices 範例段落）。

## Non-Goals

- 不提供自動遷移工具，也不保留讀取舊目錄的 fallback；既有實例由使用者手動重新命名。
- 不改動 home 層 ~/.bestasr/context/ 或 --context-dir flag 的行為。
- 不改動 context 目錄的內部結構（context.json、voices 子資料夾等）。
- 不負責遷移本機既有實例（例如 indigenous、storyline 專案下的舊目錄）；那屬於 release 後的下游手動動作。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `context-calibration`：工作目錄層 context 目錄的解析路徑由 bestasr-context 改為 .bestasr/context（normative 變更，breaking），並移除舊路徑的 fallback。

## Impact

- Affected specs: context-calibration (modified)
- Affected code:
  - Modified:
    - Sources/BestASRKit/Context/ContextLoader.swift
    - Tests/BestASRKitTests/ContextTests.swift
    - openspec/specs/context-calibration/spec.md
    - plugins/bestasr/skills/context-ingest/SKILL.md
    - plugins/bestasr/skills/transcript/SKILL.md
    - README.md
    - CHANGELOG.md
  - New: (none)
  - Removed: (none)
