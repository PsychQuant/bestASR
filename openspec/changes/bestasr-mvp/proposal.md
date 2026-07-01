## Why

現有本機 ASR 工具要求使用者自行決定 backend（whisper / faster-whisper / whisper.cpp / mlx-whisper）、模型大小（tiny … large-v3-turbo）、compute type（fp16 / int8 / quantized）與加速方式（CPU / CUDA / Metal / MLX）。對非專家這是一道高牆，選錯會導致跑不動、爆記憶體或速度極慢。bestASR 把這一整串決策自動化：偵測電腦環境與音訊後，給出**可解釋**的推薦（backend + 模型 + compute type + 理由），並可直接執行轉錄。專案的護城河是「推薦準確、fallback 穩定、解釋清楚」，而非支援最多模型。

## What Changes

- 新增 `bestasr` Python CLI 套件（Python 3.10+、pyproject.toml、entry point `bestasr`）。
- 三個核心指令：`diagnose`（環境診斷 + 推薦）、`recommend`（只推薦不執行、輸出 JSON）、`transcribe`（執行轉錄）。輔助指令 `list-backends` / `list-models`。
- **Detection**：偵測 OS / CPU / RAM / GPU / VRAM / CUDA / Metal / MLX / AVX2 / AVX512 / ffmpeg 是否存在，以及音訊長度 / 格式 / sample rate / channel / 語言。
- **Routing**（核心）：rule-based recommendation，含 profile 權重（fast / balanced / accurate）、候選評分、記憶體不足時的模型降級鏈、backend 不可用時的 fallback，並產出 `reason` 與 `warnings` 清單以支援 `--explain`。
- **Engines**：共同 `BaseEngine` 介面（`is_available` / `transcribe` / `estimate_requirements`）+ faster-whisper、whisper.cpp、mlx-whisper 三個實作；未安裝的 backend 以 `is_available()` graceful 回報而非 crash。
- **Output**：txt / json / srt / vtt 四種 writer。
- CLI 旗標：`--profile` / `--backend` / `--model` / `--language` / `--format` / `--output` / `--explain`。
- 全面 type hints + dataclasses（`SystemInfo` / `AudioInfo` / `ASRRecommendation` / `Transcript` / `TranscriptSegment`）。
- 單元測試（hardware detection / router decisions / output writers）與 README + examples。

## Non-Goals

範圍排除與被否決的方案記錄於 design.md 的 Goals / Non-Goals 區塊（例如：不重新訓練模型、第一版不做 Web UI / diarization / 串流 / 翻譯 / 雲端 API / benchmark leaderboard）。

## Capabilities

### New Capabilities

- `system-detection`: 偵測系統硬體、作業系統、加速後端可用性、音訊檔屬性與語言，產出 `SystemInfo` / `AudioInfo`。
- `asr-routing`: 依環境、音訊與 profile 做 rule-based 推薦，含評分、模型降級、fallback 與可解釋的 reason/warnings，產出 `ASRRecommendation`。
- `asr-engine`: 定義共同 `BaseEngine` 介面並封裝 faster-whisper / whisper.cpp / mlx-whisper，統一 `Transcript` 輸出與可用性偵測。
- `transcript-output`: 將 `Transcript` 寫成 txt / json / srt / vtt 格式。
- `cli`: 提供 `diagnose` / `recommend` / `transcribe` 等指令與旗標，串接 detection → routing → engine → output。

### Modified Capabilities

(none)

## Impact

- Affected specs: 5 個新 capability（system-detection、asr-routing、asr-engine、transcript-output、cli）。
- Affected code:
  - New:
    - pyproject.toml
    - README.md
    - bestasr/__init__.py
    - bestasr/cli.py
    - bestasr/detect/__init__.py
    - bestasr/detect/system.py
    - bestasr/detect/hardware.py
    - bestasr/detect/acceleration.py
    - bestasr/detect/audio.py
    - bestasr/detect/language.py
    - bestasr/router/__init__.py
    - bestasr/router/rules.py
    - bestasr/router/scorer.py
    - bestasr/router/profiles.py
    - bestasr/router/recommendation.py
    - bestasr/engines/__init__.py
    - bestasr/engines/base.py
    - bestasr/engines/faster_whisper_engine.py
    - bestasr/engines/whisper_cpp_engine.py
    - bestasr/engines/mlx_whisper_engine.py
    - bestasr/output/__init__.py
    - bestasr/output/txt.py
    - bestasr/output/json_writer.py
    - bestasr/output/srt.py
    - bestasr/output/vtt.py
    - bestasr/output/_timecode.py
    - bestasr/models/__init__.py
    - bestasr/models/registry.py
    - bestasr/models/requirements.py
    - bestasr/utils/__init__.py
    - bestasr/utils/ffmpeg.py
    - (logging uses stdlib print for CLI output; output-path derivation is inlined in bestasr/cli.py rather than a separate paths module)
    - tests/test_hardware_detection.py
    - tests/test_router.py
    - tests/test_output_formats.py
    - examples/basic_transcribe.sh
    - examples/diagnose.sh
    - examples/recommend.sh
  - Modified: (none — greenfield)
  - Removed: (none)
- Dependencies（多為選用 / 平台相關，缺少時 graceful degrade）:
  - faster-whisper（CTranslate2，CUDA / CPU）
  - mlx-whisper（Apple Silicon / Metal）
  - whisper.cpp binding（pywhispercpp 或 subprocess 呼叫 whisper-cli）
  - psutil（RAM / CPU 偵測）
  - ffmpeg（外部工具，音訊解碼 / 探測）
