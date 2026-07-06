## Context

#52：權重信任完全委託 FluidAudio resolver（HF main HEAD）。cache 落 `~/Library/Application Support/FluidAudio/Models/<repo>/`，bestASR 呼叫 seam 恰 3 處。

## Goals / Non-Goals

**In**：post-download 逐檔 SHA256 驗證、TOFU manifest、pin script、3 seams、README。
**Out**：自建下載器、上游 PR、首次下載污染防禦（明載邊界）。

## Decisions

### D1 — TOFU→pin 信任模型，unpinned 警告放行、pinned mismatch fail-loud

manifest 未收錄的 model：印警告（含 pin 指引）繼續——否則新模型（如 #50 的 Paraformer）首次使用即死鎖。已收錄者 mismatch：throw fail-loud——寧可停機不可靜默用漂移權重。信任錨 = maintainer 首測時的 cache 狀態（與 #34 corpora tsv-digest 同模型）。Deletion test：拿掉 verifier = 回到純 TOFU 無偵測——非 pass-through。

### D2 — verifier 落在 bestASR wrapper 層（3 seams），不 fork FluidAudio

下載 API 是 FluidAudio 的，驗證是 bestASR 的政策——政策疊在 seam 上（下載完成後、模型使用前），不動 vendored code。3 個 seam 都在 factory/lazy-init 路徑，每 process 首次 load 驗一次（非每次 transcribe）。Parakeet 用分離 API（`download` → verify → `load(from:)`）——漂移權重到不了 CoreML 編譯；DiarizerModels 無分離 API → load 後、處理任何音訊前驗（保護後續 process，明載限制）。VAD repo **不驗**——`DiarizerModels` 只下載 speaker-diarization（segmentation+embedding），本機 `silero-vad-coreml` 目錄是舊版殘留（0.15.4 的 folderName 已 strip `-coreml`），pin 它會死鎖 fresh install。

### D3 — manifest 為 JSON resource：`{repo: {relativePath: sha256}}`

逐檔記錄（42 檔可讀可 diff）；驗證 = 遍歷 manifest 該 repo 的每個 entry，對 cache 同 relative path 算 SHA256 比對；manifest 有列但 cache 缺檔 = mismatch（防刪檔降級）。cache 多出的檔（FluidAudio 附帶新檔）不擋——pin 的語意是「我依賴的檔案沒變」而非「目錄凍結」。

### D4 — pin script 走 bash+shasum（zero 新依賴），manifest 提交進 git

`scripts/pin-weights.sh [repo…]`：對 cache 現況產 JSON（穩定排序）寫入 Sources resource 路徑。升級 FluidAudio 版本的流程 = 重跑 script + review diff + commit——manifest diff 即權重變更的審計軌跡。

## Risks / Trade-offs

- FluidAudio 升版權重更新 → fail-loud 直到重 pin——預期行為（升版流程含重 pin），README 寫明
- 42 檔逐檔 SHA256 ~475MB 首次 load 增加 ~1-2s——每 process 一次，可接受；後續可加 mtime 快取（不在本 change）

## Migration Plan

新機制純增量：無 manifest 時所有 model 走「警告放行」與現狀等價。Rollback = revert（verifier 移除即回現狀）。

## Open Questions

（無）
