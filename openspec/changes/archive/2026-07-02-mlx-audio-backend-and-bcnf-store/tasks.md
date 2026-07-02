## Phase 1 — BCNF store 基座

- [x] 1.1 (D3; req: BCNF four-table store with JSON records) `Sources/BestASRKit/Store/StoreTables.swift`：四表 row 型別（MachineRow/ModelRow/CorpusRow/MeasurementRow，Codable）+ key 推導（machine_id/model_id/corpus_id）；測試：Codable round-trip、key 決定性、BCNF 鍵唯一性參數化（`StoreTablesTests`）
- [x] 1.2 (D3; req: BCNF four-table store with JSON records; Append-only measurements with latest projection; Corrupt rows degrade loudly, not fatally) `Sources/BestASRKit/Store/BenchmarkStore.swift`：四張 JSONL 載入/append、`latestMeasurements()` 投影、壞行跳過含表名+行號警告；測試：暫存目錄 round-trip、latest 取 measured_at 最大、壞行不 fatal（`BenchmarkStoreTests`）
- [x] 1.3 (D4; req: One-time legacy migration) 舊檔遷移：`BenchmarkStore.load()` 偵測 legacy `benchmarks.json` → 分解四表 → 改名 `.bak`、冪等；測試：合成舊檔 N 筆 → 四表重建 recommend 輸入等值、二次 load 不重跑

## Phase 2 — Model Grid

- [x] 2.1 [P] (D5; req: Full-family catalog; Priority tiers gate the default sweep; Unverified repo ids are marked, never guessed; Unmeasured is a join fact, not a marker) `Sources/BestASRKit/Models/ModelGrid.swift`:15 家族 × 尺寸 × 量化目錄（含既有兩 backend 現行模型，priority 1；D5 先行集/2/3 分層；hf_repo 未核者 `verified:false`）；`rows(backend:priorityCeiling:)` 過濾;測試：全家族枚舉 ≥30、priority 過濾、先行集 4 row 鎖定（spec Example）、unverified 標記（`ModelGridTests`）
- [x] 2.2 [P] (D5; req: Full-family catalog — registry 橋接) ModelRegistry 橋接：`supportedModels`/`quantizations(for:model:)`/`requirements(for:)` 改由 grid 投影（既有測試不動即綠為驗收）；cold-start prior 讀 grid est_memory

## Phase 3 — MLXAudioEngine

- [x] 3.1 [P] (D1; req: Persistent JSON-lines worker per model — 協定面) Worker 協定純函式：request/response JSON 編解碼、ready 行、error row（`Sources/BestASRKit/Engines/MLXWorkerProtocol.swift`）;測試鎖 spec Example 的兩行（`MLXWorkerProtocolTests`）
- [x] 3.2 (D1; req: Persistent JSON-lines worker per model — worker 實體) `Sources/BestASRKit/Engines/mlx_worker.py`:`--model <hf_repo>`、mlx_audio.stt Python API、載入後印 ready、逐行處理、錯誤不退出；shell 語法煙測（`python3 -m py_compile`）
- [x] 3.3 (D2; req: Honest availability via dedicated venv; Worker lifecycle follows the keep-current cache; Output normalization and prompt honesty; Availability detection is graceful) `Sources/BestASRKit/Engines/MLXAudioEngine.swift`：BackendID `.mlxAudio` 第三成員；`WorkerTransport` seam（真實 = Process stdin/stdout；測試注入閉包）；CreateOnceStore<worker> + retainOnly 殺舊 process；`isAvailable()` venv import 探測（memoized）；venv 缺 → 安裝指令錯誤；prompt 忽略 + explain 揭露；segments 缺 → 全文單 segment；測試：transport spy（請求內容、映射、error row、ready 逾時）、availability false 路徑、eviction 殺 process（`MLXAudioEngineTests`）
- [x] 3.4 (D6; req: Enumerate candidate configurations — CLI 面) CommandCore/CLI 接線：engines 列表加入、list-backends/list-models 顯示、`--all-grid` 旗標進 benchmark；既有 135 tests 保綠

## Phase 4 — Benchmark/Router 改讀 store

- [x] 4.1 (D6; req: Enumerate candidate configurations; Persist benchmark results to a machine-local cache) BenchmarkRunner：枚舉改 `ModelGrid.rows`（priority 預設 ≤1、`--all-grid` 放寬）；量測寫 `store.append`；MeasuredCandidate 保形；BenchmarkCache 標 deprecated 只剩遷移
- [x] 4.2 (D7; req: Rank candidates by measured benchmark data) Router/Ranking/Report：改讀 latest 投影 join grid/corpora（Ranking 介面吃投影 struct 不變）；per-language 過濾明確化；`RouterTests`/`BenchmarkTests`/`CLITests` fixture 改走 store（注入暫存 store 路徑）
- [x] 4.3 全套測試綠（含既有 135 + 新增）

## Phase 5 — Corpora

- [x] 5.1 [P] (D8; req: Corpus registry keyed by content hash; corpus add and list subcommands) `Sources/BestASRKit/Corpora/CorpusRegistry.swift` + `corpus add/list` 子命令：hash、AudioProber duration、同 hash 更新 path 不重複；測試：add/list round-trip、重註冊冪等（`CorpusRegistryTests`）
- [x] 5.2 [P] (D8; req: English standard set is scriptable and verified) `scripts/fetch-corpora.sh`：jfk + OSR 下載、afconvert 16k、sha256 pin 驗證、呼叫 corpus add；本機實跑一次入 registry

## Phase 6 — 真實煙測 + 文件

- [x] 6.1 (D9, D10; req: Persistent JSON-lines worker per model — 真實驗收) venv 建置 + priority-1 最小模型（moonshine base 或 parakeet 0.6b）真實端到端：`bestasr transcribe`（en）+ `bestasr benchmark --backends mlx-audio`（先行集掃描、量測入 store）；實測輸出貼 issue #14
- [x] 6.2 (D8, D9; req: corpus add and list subcommands — zh 驗收) zh 語料註冊煙測（使用者素材或既有 zh 樣本 corpus add）+ zh benchmark 一輪（能跑則跑，無素材則記錄 blocked-on-material）
- [x] 6.3 README（第三 backend + corpus 工作流 + grid/priority 說明）、CHANGELOG Unreleased；`swift test` 全綠終驗
