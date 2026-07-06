## 0. Design traceability

- D1 — TOFU→pin 信任模型，unpinned 警告放行、pinned mismatch fail-loud → tasks 1.1, 1.2
- D2 — verifier 落在 bestASR wrapper 層（3 seams），不 fork FluidAudio → task 2.1
- D3 — manifest 為 JSON resource：`{repo: {relativePath: sha256}}` → tasks 1.1, 1.2
- D4 — pin script 走 bash+shasum（zero 新依賴），manifest 提交進 git → task 2.2

## 1. WeightVerifier（TDD）

- [x] 1.1 (design D1/D3; spec weight-pinning "Downloaded model weights verify against the pinned manifest" + "Unpinned models warn and proceed (TOFU window)") RED：測試——pinned 全符通過、單檔 digest 漂移 throw（錯誤含 model 與 path）、manifest 有列 cache 缺檔 = mismatch、cache 多餘檔不擋、unpinned model 警告放行。先紅。驗證：目標測試紅
- [x] 1.2 GREEN：`WeightVerifier.verify(repo:cacheDir:)` 實作＋manifest resource 載入。驗證：全套件綠

## 2. Seams ＋ script

- [x] 2.1 (design D2) 3 個 seam 掛驗證（ParakeetEngine factory、DiarizationEngine、SpeakerEnroller 的 download 後 load 前）。驗證：既有測試綠（spy pipeline 不觸發 verifier 的真實路徑）
- [x] 2.2 (design D4; spec weight-pinning "The pinning script regenerates the manifest from the local cache") `scripts/pin-weights.sh`＋以本機 cache 實測產首版 manifest 入 repo（3 repos／42 檔）；重跑 byte-identical。驗證：manifest 存在、二跑 idempotent

## 3. 收尾

- [x] 3.1 README 供應鏈段更新（trade-off 聲明 → 機制描述＋升版重 pin 流程）＋CHANGELOG。驗證：條目指向 #52
