---
description: 調查最新的 ASR 模型（WhisperKit / mlx-audio / whisper.cpp / FluidAudio 生態）並評估納入 bestASR 的接線工作。當開發者說「有什麼新的 ASR 模型」「查最新模型」「把 X 模型加進來」「更新 model catalog」時使用。dev-only：只在 bestASR repo 內可見，不隨 plugin 發佈。
---

# ASR Model Scout — 查最新模型並納入 bestASR

開發者專用。兩階段：**偵察**（查生態有什麼新模型）→ **納入**（把選定模型接進 catalog）。使用者只要偵察就停在偵察，不要順手改 code。

## 階段 1：偵察（read-only）

用 WebSearch / WebFetch 掃這些來源，找**本 repo 尚未收錄**的模型或新版本：

| 生態 | 來源 | 對應 backend |
|------|------|--------------|
| WhisperKit (CoreML) | `huggingface.co/argmaxinc/whisperkit-coreml`（檔案樹）、argmaxinc GitHub releases | `whisperkit` |
| whisper.cpp (GGML) | `huggingface.co/ggerganov/whisper.cpp`、ggml-org releases | `whisper.cpp` |
| mlx-audio | `huggingface.co/mlx-community`（ASR 類）、mlx-audio GitHub | `mlx-audio` |
| FluidAudio | FluidInference GitHub（Parakeet / Paraformer / SenseVoice 新版）| `fluid-*` |
| 生態級 SOTA | HF ASR leaderboard（open_asr_leaderboard）、近期 ASR model release 新聞 | 評估是否值得開新 backend |

比對基準（現有收錄）：
- `Sources/BestASRKit/Models/ModelRegistry.swift` — `supportedModels`（whisper 尺寸階梯）
- `Sources/BestASRKit/Models/ModelGrid.swift` — mlx-audio catalog（families + priority tiers + **pinned revisions**）
- `Sources/BestASRKit/Supply/weights-manifest.json` — weight digest pins

輸出偵察報告：模型名、來源 repo id、授權、語言覆蓋（**zh/ja 是本 repo 的主戰場**，純英文模型價值低）、量化變體、記憶體需求估計、與現有最接近模型的預期差異。**repo id 與 revision 一律從 HF 頁面實查，不憑記憶猜**（repo 紀律：「Repo ids are never guessed — a pinned revision proves the probe」）。

## 階段 2：納入（走 IDD，不直接動手）

納入是正式 code change：先 `/idd-issue` 開 feature issue（引用偵察報告），再走 diagnose → implement。接線點依 backend 而異：

| Backend | 要改的地方 |
|---------|-----------|
| whisper 家族新尺寸 | `ModelRegistry.swift`：`supportedModels`、`downgradeChain`、`profileModels`、`quantizations`、`requirements`（記憶體估計）|
| mlx-audio 新 family/版本 | `ModelGrid.swift`：加 row（family、size、**pinned revision**、priority tier）|
| 權重 pin | `Supply/weights-manifest.json`：加 digest（WeightVerifier 會 fail-loud 驗 drift）|
| FluidAudio 新模型 | 通常是 Package.swift 的 FluidAudio exact-pin bump + `ChineseFamilyEngine`/`ParakeetEngine` 對應 |

必守紀律：
- **每個新模型都要 pinned revision + digest**，不收 `main`/`latest` 浮動引用（supply-chain 紀律，`WeightVerifierTests`）。
- 對應測試要跟上：`ModelRegistryTests`（每個 supported model 有正面記憶體估計、id 唯一）、`ModelGridTests`（family 數、pinned rows round-trip）。
- 納入後跑 `bestasr benchmark` 在 zh/ja/en 語料實測，數字進 benchmark store 才算「measured」；沒測過的模型 router 只會以 cold-start prior 對待。
- **不動 `benchmarks/baseline.json`**——那是 regression gate 的 golden，換 reference model 是獨立的重大決策。

## 邊界

- 本 skill 是 dev-only（project skill），不隨 plugin 發佈；shipped skills 在 `plugins/bestasr/skills/`。
- 偵察報告若要留檔，放 issue body 或 `references/`，不進 `Sources/`。
