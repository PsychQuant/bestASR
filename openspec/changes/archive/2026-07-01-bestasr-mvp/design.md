## Context

bestASR 是一個 greenfield Python CLI 專案，目標是「本機 ASR 模型的智慧路由器」。它不訓練模型，而是編排既有的本機 ASR backend。核心痛點：使用者不知道自己的機器該用哪個 backend / 模型 / compute type / 加速方式，選錯就跑不動、爆記憶體或極慢。

本 change 一次交付整個 MVP（使用者決定），橫跨五個子系統：Detection、Routing、Engine、Output、CLI。逐字需求原文見 `docs/design-brief.md` 與 tracking issue PsychQuant/bestASR#1；本文件是對該草案的技術詮釋。

限制與現況：
- 相依（faster-whisper / mlx-whisper / whisper.cpp / ffmpeg）多為平台相關或選用；設計必須在缺件時 graceful degrade，不能 import 失敗即整支 crash。
- 目標平台涵蓋 Apple Silicon（Metal / MLX）、NVIDIA CUDA、以及 CPU-only 機器。
- 首要品質軸是**可解釋性**：每個推薦都要帶 `reason` 清單。

## Goals / Non-Goals

**Goals:**

- 三個可用指令：`diagnose`、`recommend`、`transcribe`，外加 `list-backends` / `list-models`。
- 依環境 + 音訊 + profile 產出**可解釋**的推薦（backend / model / compute_type / reason / warnings）。
- 缺 backend / 缺 ffmpeg / 記憶體不足時有明確、穩定的 fallback 與降級行為。
- 全面 type hints、dataclasses、單元測試（detection / router / output）。

**Non-Goals（第一版明確排除）:**

- 不重新訓練或 fine-tune 任何 ASR 模型。
- 不做 Web UI、SaaS、桌面 app、server API。
- 不做人聲分離、speaker diarization、即時串流轉錄、自動摘要、翻譯。
- 不做模型 benchmark leaderboard、不接雲端模型 API。
- 不追求支援「最多」backend；第一版只做 faster-whisper / whisper.cpp / mlx-whisper（Parakeet / Canary / wav2vec2 / seamless 留待後續）。
- 實測 benchmark 數字不進 MVP；router 用**靜態特性表**估算，不做線上量測。

## Decisions

### D1: 五層單向管線架構（CLI → Detection → Routing → Engine → Output）

各層單向依賴、介面清楚：CLI 解析指令 → Detection 產生 `SystemInfo` / `AudioInfo` → Routing 產生 `ASRRecommendation` → Engine 依推薦執行得 `Transcript` → Output 寫檔。好處是每層可獨立測試（router 可用假的 SystemInfo 測、output 可用假的 Transcript 測，不需真的轉錄）。
- 替代方案：把偵測與路由揉在 CLI 內。否決，因為無法單獨測試 router，也違反「router 是核心」的定位。

### D2: Router 以 rule-based 為主、scoring 為輔

先用明確規則決定 backend（見 D3 決策表），再用 profile 加權評分在可行候選中挑模型 + compute type。`scorer` 計算 `score = Σ profile_weight[dim] × metric[dim]`，dim ∈ {speed, accuracy, memory_fit, stability}，metric 來自靜態特性表（`models/registry.py`、`models/requirements.py`）。
- 替代方案：純 ML / 純線上 benchmark。否決，MVP 要 deterministic、可解釋、可測試；線上量測慢且不穩定。

### D3: Backend 選擇決策表（規則優先序）

依偵測結果套用（由上而下，第一個成立者勝出），且所選 backend 必須 `is_available()`：
1. Apple Silicon 且 mlx-whisper 可用 → `mlx-whisper`（compute `fp16`）
2. NVIDIA GPU + CUDA 且 faster-whisper 可用 → `faster-whisper`
3. CPU-only（或前述都不可用）→ `whisper.cpp`（quantized 友善）
4. RAM 很小 → 傾向 `whisper.cpp` + 較小 quantized 模型
使用者以 `--backend` 明確指定時跳過決策表，但若該 backend 不可用則回報 warning 並 fallback。

### D4: 記憶體不足時的模型降級鏈

若所選模型的估算需求 > 可用記憶體（RAM 或 VRAM，視 backend），沿鏈降級直到放得下：`large-v3 → medium → small → base → tiny`；`large-v3-turbo` 併入 large 級處理。每次降級都 append 一則 `warning` 與 `reason`，讓 `--explain` 看得到「為何沒用更大的模型」。

### D5: compute_type 選擇規則

- `mlx-whisper`：`fp16`（Apple Silicon unified memory）。
- `faster-whisper` on CUDA：VRAM 充足 → `fp16`；VRAM 不足 → `int8_float16` → `int8`。
- `whisper.cpp` on CPU：quantized（如 `q5_0` / `q8_0`）或 `int8`。
選擇結果與理由寫進 `ASRRecommendation.compute_type` 與 `reason`。

### D6: BaseEngine 介面與 backend 可用性偵測（graceful degrade）

所有 engine 實作 `is_available() -> bool`、`transcribe(audio_path, options) -> Transcript`、`estimate_requirements(model_name) -> ModelRequirements`。`is_available()` 以 lazy import 探測底層套件，import 失敗回 `False` 而非拋例外。Routing 只會選 `is_available()` 為真的 backend。
- 替代方案：在 package 載入時 hard import 所有 backend。否決，會讓沒裝某 backend 的機器整支 crash。

### D7: Detection 以標準庫 + psutil + import 探測為主

- OS / CPU：`platform`、`os`。
- RAM：`psutil`（缺 psutil 時 fallback 到 OS 專屬查詢並降級精度 + warning）。
- CUDA / Metal / MLX：以「嘗試 import 對應套件 / 查詢環境」探測可用性，而非要求硬相依。
- AVX2 / AVX512：讀 CPU flags（Linux `/proc/cpuinfo`、macOS `sysctl`）。
- ffmpeg：`shutil.which("ffmpeg")`。

### D8: 音訊探測與語言偵測

- 音訊長度 / 格式 / sample rate / channel：優先用 `ffprobe`（隨 ffmpeg），缺 ffmpeg 時以副檔名 + 有限 header 解析並降級 + warning。
- 語言：`--language` 明確指定優先；`auto` 時 MVP 交由 engine 自身語言偵測，router 僅用「是否多語言/指定語言」影響模型偏好（見 D2）。

### D9: Profile 權重表

`fast` / `balanced` / `accurate` 三組固定權重（speed / accuracy / memory_fit / stability），定義於 `router/profiles.py`，數值取自草案 §7.1。預設 `balanced`。

### D10: CLI 以標準庫 argparse 實作

用 `argparse`（subcommands）避免額外相依，符合「缺件仍可跑診斷」的精神。`--explain` 讓 `transcribe` 額外印出 `ASRRecommendation.reason` / `warnings`；`recommend` 一律輸出 JSON。
- 替代方案：typer / click。否決（MVP 不值得多一個相依；診斷工具應在最小環境可跑）。

## Implementation Contract

**可觀察行為（指令）：**

- `bestasr --help`：印出 usage 與子指令清單，exit 0。
- `bestasr diagnose`：印出 System（OS / CPU / RAM / 加速可用性）+ Recommendation（backend / model / compute / profile）+ Reason 文字段落，exit 0。不需要音訊檔。
- `bestasr recommend <audio>`：**只**輸出一個 JSON 物件到 stdout（見下方 shape），不執行轉錄，exit 0。
- `bestasr transcribe <audio>`：執行轉錄，依 `--format` 寫出（預設 txt、預設寫到 `<audio 基名>.<ext>` 或 `--output`）；加 `--explain` 時額外把 reason / warnings 印到 stderr。
- `bestasr list-backends` / `list-models`：列出支援項目與各自 `is_available()` / 特性。

**資料形狀（dataclasses，型別如草案 §8/§9）：**

- `SystemInfo`：os / cpu / ram_gb / gpu / vram_gb / has_cuda / has_metal / has_mlx / has_avx2 / has_avx512 / has_ffmpeg。
- `AudioInfo`：path / duration / format / sample_rate / channels / language。
- `ASRRecommendation`：backend / model / compute_type / profile / language / estimated_speed / estimated_accuracy / reason: list[str] / warnings: list[str]。
- `TranscriptSegment`：id / start / end / text / confidence。
- `Transcript`：text / language / duration / segments / backend / model。

**`recommend` 的 JSON shape（範例）：**

```json
{
  "backend": "faster-whisper",
  "model": "medium",
  "compute_type": "int8_float16",
  "profile": "balanced",
  "language": null,
  "estimated_speed": "medium",
  "estimated_accuracy": "high",
  "reason": ["CUDA GPU detected", "VRAM below 8 GB", "balanced profile selected"],
  "warnings": []
}
```

**失敗模式：**

- Backend 未安裝：`is_available()` 回 False；router 不選它；若使用者 `--backend` 指定它 → 印 warning + fallback 到次佳可用 backend；若完全無可用 backend → 非零 exit + 清楚錯誤訊息（列出安裝指引）。
- ffmpeg 缺失：偵測降級（副檔名推斷）+ warning，不 crash；`transcribe` 若該 backend 需 ffmpeg 解碼則報明確錯誤。
- 記憶體不足：走 D4 降級鏈；若連 tiny 都放不下 → warning + 仍嘗試 tiny（或非零 exit，視 backend），行為在 spec scenario 明定。
- 找不到音訊檔 / 不支援格式：非零 exit + 明確訊息。

**驗收（可驗證）：**

- `pytest` 綠：`tests/test_hardware_detection.py`（detection 用 mock/monkeypatch）、`tests/test_router.py`（給定假 SystemInfo/AudioInfo → 斷言 backend/model/compute/降級/reason）、`tests/test_output_formats.py`（給定假 Transcript → 斷言 txt/json/srt/vtt 內容與時間碼格式）。
- `bestasr diagnose` 在本機（Apple Silicon 或 CUDA 或 CPU-only）輸出對應且合理的推薦與理由。
- `bestasr recommend sample.wav` 輸出可被 `json.loads` 解析且含上述鍵。

**Scope 邊界：**

- In scope：五層實作、rule-based router + scoring + 降級 + fallback、三 backend 封裝、四輸出格式、CLI + 旗標、單元測試、README/examples。
- Out of scope：真實 benchmark 量測、diarization、串流、翻譯、GUI、雲端 API、Parakeet/Canary 等額外 backend（見 Non-Goals）。

## Risks / Trade-offs

- [靜態特性表可能與真實硬體表現有落差] → MVP 接受估算誤差；表集中在 `models/requirements.py` 便於日後校正；每個推薦都帶 reason，使用者可覆寫。
- [三個 backend 的相依安裝複雜、平台差異大] → 一律 lazy import + `is_available()`；CI/測試用 mock，不真的裝 backend。
- [whisper.cpp 無官方 Python 套件，binding 分歧（pywhispercpp vs subprocess）] → 介面層吸收差異；MVP 先支援一種取得方式，`is_available()` 誠實回報。
- [`output/json` 命名與標準庫 json 衝突風險] → 模組命名為 `output/json_writer.py` 規避 shadowing。
- [語言偵測 MVP 交給 engine，router 對語言的利用有限] → 標為 known limitation；`--language` 明確指定時行為明確，auto 時以 engine 為準。
