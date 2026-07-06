## Context

#51：候選池限 Swift engines；15 家族 reference catalog 無掛載機制。#20 移除 mlx-audio 內建 backend 的 containment 需求清單（Python venv／worker 生命週期／上游 churn）是設計起點。使用者裁決立即設計，consumer = mlx-audio CLI。

## Goals / Non-Goals

**In**：協定 spec、ExternalProcessEngine、registry config、BackendID.mlxAudio、grid 升級規則、mlx-audio adapter＋venv bootstrap＋一家族實測。
**Out**：server mode（v2）、逐家族 adapter、既有 engines 改動。

## Decisions

### D1 — 協定：argv spawn + stdout 單一 JSON，版本欄位開路

呼叫：`<command...> transcribe --audio <path> --model <model> [--language <code>] [--hf-repo <repo>] [--revision <rev>]`——argv 陣列直接 `Process`，**絕不經 shell**（注入面歸零）。成功 = exit 0 + stdout 單一 JSON：`{"protocol":1,"text":"...","duration":12.3,"segments":[{"start","end","text"}]?}`；失敗 = 非零 exit，stderr 進 TranscriptionError。`protocol` 欄位讓 v2（server mode、streaming）能相容演進。segments 選配——text-only 輸出走單段全文（沿 #50 語意）。Deletion test：拿掉 protocol 驗證，未來 v2 adapter 對 v1 host 會靜默錯配。

### D2 — BackendID 封閉 enum + 每工具一 case，不做動態 id

動態 backend id（struct wrapper）漣漪到 store/router/grid/CLI 全 codebase 且弱化型別安全。v1 加 `.mlxAudio = "mlx-audio"` 一個 case——grid 常數 `backendMLXAudio` 已存在，store 的 backend 欄位是 String 本就相容。未來每個新工具＝一個 case + registry entry 的小 diff。

### D3 — Containment（#20 需求清單的正面回應）

- **venv 歸 adapter 自管**：registry 指向 wrapper script（shebang → 自己的 venv python）；bestASR 本體零 Python 知識。`adapters/mlx-audio/setup.sh` 建 `~/.bestasr/adapters/mlx-audio/`（venv＋wrapper），repo 只進 script 原始碼
- **無常駐 worker**：每呼叫一 process——無生命週期管理、無殭屍 worker、crash 隔離天然
- **上游 churn**：adapter 壞 → 非零 exit → fail-loud TranscriptionError；絕不 fallback 到別的 backend（使用者顯式選了它）
- **timeout**：`max(120s, 音長×4)`——防 adapter 掛死；超時 SIGTERM → 稍候 SIGKILL

### D4 — grid reference rows 條件升級，路由仍 measured-only

mlx-audio rows（15 家族、hfRepo＋revision pinned）在「registry 有 mlx-audio 且 command 存在」時枚舉為 runnable 候選；未註冊機器上行為與現狀 byte-identical。cold-start prior 不變（whisper）——external 家族只能靠 measured 數據贏路由（與 #35/#50 同紀律）。

### D5 — 量測可比性：RTF 誠實含 process 開銷，spec 明載語意差異

內建 backend 的 X-REAL 排除 warmup（model load 一次性）；external 每呼叫重新 spawn＋載模型——結構性差異**不掩飾**：benchmark 對 external rows 的 X-REAL 含全部 process 時間，spec 明載「external X-REAL 是端到端語意」。WER/CER 走同一 normalizer 管線，品質面完全可比。

### D6 — registry config 位置與 schema

`~/.bestasr/engines.json`：`{"engines":[{"id":"mlx-audio","command":["/Users/x/.bestasr/adapters/mlx-audio/run.sh"]}]}`。與 store（`~/.bestasr/store/`）、corpora（`~/.bestasr/corpora/`）同層慣例。id 必須匹配已知 BackendID rawValue（未知 id → 警告忽略，fail-soft——config 是使用者手寫面）。

## Risks / Trade-offs

- mlx-audio 上游 API churn → adapter 壞掉 fail-loud、修 adapter 不動 bestASR（隔離達成）
- 每呼叫載模型的 RTF 劣勢 → 誠實量測；v2 server mode 是解方空間
- venv ~GB 級磁碟 → setup.sh 是顯式 opt-in，README 明載

## Migration Plan

純增量：無 registry config 時零行為變化。Rollback = revert＋刪 `~/.bestasr/adapters/`。

## Open Questions

（無）
