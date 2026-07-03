## Phase 1 — 刪除（D3 順序：測試 → 實作 → enum）

- [x] 1.1 (D3; req: Honest availability via dedicated venv; Persistent JSON-lines worker per model; Worker lifecycle follows the keep-current cache; Output normalization and prompt honesty — 全數 REMOVED) 刪 `Tests/BestASRKitTests/MLXAudioEngineTests.swift`（含 MLXWorkerProtocolTests / RevisionPinTests）與 `RouterTests` 內 `MLXColdStartRoutingTests`；`git rm` 後 build 列殘留
- [x] 1.2 (D3; req: Persistent JSON-lines worker per model — 實體移除) 刪 `Sources/BestASRKit/Engines/MLXAudioEngine.swift`、`MLXWorkerProtocol.swift`、`Engines/mlx_worker.py`；`Package.swift` 移除 resources 條目
- [x] 1.3 (D3; req: Availability detection is graceful — mlx 例句退場; Enumerate candidate configurations — mlx 分支移除) `BackendID` 移除 `.mlxAudio`；依編譯錯誤修剪 Router（availability 鏈、family/size 推斷、mlx cold-start、pair-guard）、CommandCore（live() 名單、promptSupported）、BenchmarkRunner（mlx 分支）、CLI help；驗收：`grep -riE "mlxaudio|mlx_worker|MLXWorker" Sources/ Tests/` 僅剩 ModelGrid 資料/註解

## Phase 2 — Grid reference 語意（D1）

- [x] 2.1 (D1; req: Full-family catalog / Priority tiers) ModelGrid 註解改 reference-catalog 語意；`list-models` 段標題「mlx-audio reference catalog (backend not bundled)」；`ModelGridTests` 對齊（15 家族 ≥30 rows 保留、先行集 Example 改 reference 措辭、pin 不變式續鎖）
- [x] 2.2 (D2; req: Reference rows never enumerate; Enumerate candidate configurations) 濾除鎖定測試：store 含 "mlx-audio" 量測時 recommend 靜默濾除不 crash；enumerate 無 reference 候選

## Phase 3 — 收斂與真實驗收

- [x] 3.1 全套測試綠；README（Backends 段刪 mlx-audio 安裝、加 reference 說明）；CHANGELOG `### Removed`
- [x] 3.2 (Implementation Contract) 真實 smoke：`list-models` 顯示 reference 段、`benchmark` 雙 backend 掃描正常、`recommend`（store 帶舊 mlx 量測）路由到可用 backend；#18/#16 re-scope comments
