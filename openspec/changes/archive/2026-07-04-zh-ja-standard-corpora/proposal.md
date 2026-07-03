## Why

#18（#14 close residue，經 #20 re-scope 為 zh/ja 語料建置）：管線已備（`corpus add` 是 spec 明載 zh/ja v1 路徑）但無已註冊 zh/ja 語料 → per-language 路由表空、`recommend --language zh|ja` 只能 cold-start。使用者既決方針：「要找網路上下載得到的標準檔案」，不用合成語音。

## What Changes

1. `scripts/fetch-corpora.sh` 延伸 FLEURS zh/ja：google/fleurs（CC-BY-4.0、非 gated）dev split 各取 3 句相異句（deterministic：TSV 序前 3 個相異句 id、各取首錄音），afconvert 轉 16 kHz mono int16（FLEURS 原始為 float32）、python3 stdlib 串接、SRT 逐字稿內嵌（輸入 pinned 故 deterministic）。供應鏈紀律沿 #15：dataset revision pin（`70bb2e84…`）+ raw tar digest 先驗後解析 + 轉檔後 wav digest
2. corpora spec ADDED requirement：zh/ja standard set scriptable and verified（對齊既有 en requirement 樣式）
3. 執行面（非 diff）：真實雙 backend benchmark 填 zh/ja 路由表；驗收 = `recommend --language zh|ja` 回 measured

## Impact

- Affected specs: corpora (ADDED)
- Affected code: scripts/fetch-corpora.sh、CHANGELOG.md
- Non-goals：大模型量測（#20 後 mlx 家族無執行路徑，已 re-scope 移出）；應用程式 runtime 行為零改動（變更僅及 fetch script 與文件）
