# bestASR — 原始設計草案（Design Brief）

> **這份文件是 source of truth，逐字保留使用者提供的原始設計草案，未經改寫。**
> 後續所有 Spectra proposal / spec / tasks 都是對這份草案的「詮釋與結構化」；當結構化文件與這份草案衝突時，以這份草案的原意為準，並回頭修正結構化文件。
> — 來源：使用者於 2026-07-01 透過 `/issue-driven-dev:idd-issue` 提供的專案草案
> — 保留原因：Spectra 的 proposal 是 AI 濃縮過的產物，會流失原文細節（CLI 範例、router 決策表、資料結構）。此檔逐字保存以供審計與追溯。
> — 追蹤 issue：[PsychQuant/bestASR#1](https://github.com/PsychQuant/bestASR/issues/1)（同份原文亦逐字嵌於該 issue 的 `<details>` 區塊）

---

以下為原文，逐字引用：

可以。這個專案很適合用 SDD / Spec-Driven Development 來做，因為 bestASR 的核心不是單一功能，而是一套明確的決策流程：

偵測環境 → 分析音訊 → 選擇 backend → 選擇模型 → 執行轉錄 → 輸出結果 → 解釋推薦原因

下面是一份可以直接拿去當 SDD 起點的草案。

⸻

## bestASR 專案草案

### 專案名稱

bestASR

### 一句話定位

Automatically choose the best local ASR model and backend for your machine.

### 中文定位

bestASR 是一個本機語音辨識模型智慧選擇器。它會根據使用者的電腦硬體、作業系統、可用加速後端、記憶體、音訊語言與轉錄需求，自動選擇最適合的 ASR 模型與推論 backend。

⸻

## 1. 專案目標

bestASR 的目標不是重新訓練 ASR 模型，而是解決一個實際痛點：

使用者不知道自己的電腦應該用哪個語音轉文字模型、哪個 backend、哪種 quantization、哪個模型大小。

現有工具通常要求使用者自己選：

```
tiny / base / small / medium / large-v3
fp16 / int8 / q5 / q8
CPU / CUDA / Metal / MLX
whisper / faster-whisper / whisper.cpp / mlx-whisper
```

bestASR 要把這些選擇自動化。

⸻

## 2. 核心使用場景

### 2.1 自動轉錄

```
bestasr transcribe input.mp3
```

bestASR 自動判斷最適合的 backend 與模型，然後輸出逐字稿。

⸻

### 2.2 指定策略

```
bestasr transcribe input.mp3 --profile low
bestasr transcribe input.mp3 --profile medium
bestasr transcribe input.mp3 --profile max
```

三種模式：

| Profile | 目標 |
|---------|------|
| fast | 優先速度 |
| balanced | 速度與準確度平衡 |
| accurate | 優先準確度 |

⸻

### 2.3 診斷電腦環境

```
bestasr diagnose
```

輸出範例：

```
System:
- OS: macOS
- CPU: Apple M3 Pro
- RAM: 36 GB
- Acceleration: Metal / MLX available
Recommendation:
- Backend: mlx-whisper
- Model: large-v3-turbo
- Compute: fp16
- Profile: balanced
Reason:
Apple Silicon detected with sufficient unified memory. MLX backend is recommended for local ASR on this machine.
```

⸻

### 2.4 解釋為什麼選這個模型

```
bestasr transcribe input.mp3 --explain
```

輸出範例：

```
Selected backend: faster-whisper
Selected model: medium
Selected compute type: int8_float16
Reason:
- NVIDIA GPU detected
- VRAM is 6 GB, which may be insufficient for large-v3 fp16
- Audio language appears multilingual
- medium profile prefers medium model over small
```

⸻

## 3. MVP 範圍

第一版不要做太大。建議 MVP 只做這些：

### 必做

1. CLI 工具
2. 硬體偵測
3. backend 偵測
4. 音訊基本資訊偵測
5. rule-based model router
6. faster-whisper backend
7. whisper.cpp backend
8. mlx-whisper backend
9. txt / json / srt / vtt 輸出
10. diagnose 指令
11. explain mode

### 第一版先不要做

1. Web UI
2. SaaS
3. 分離人聲
4. speaker diarization
5. 即時串流轉錄
6. 自動摘要
7. 翻譯
8. 模型 benchmark leaderboard
9. 雲端模型 API

這些可以放到後續版本。

⸻

## 4. CLI 設計

### 4.1 基本指令

```
bestasr transcribe input.mp3
```

預設行為：

```
profile = balanced
output = txt
language = auto
backend = auto
model = auto
```

⸻

### 4.2 指定輸出格式

```
bestasr transcribe input.mp3 --output transcript.txt
bestasr transcribe input.mp3 --format srt
bestasr transcribe input.mp3 --format vtt
bestasr transcribe input.mp3 --format json
```

⸻

### 4.3 指定語言

```
bestasr transcribe input.mp3 --language zh
bestasr transcribe input.mp3 --language en
bestasr transcribe input.mp3 --language ja
```

⸻

### 4.4 指定 backend

```
bestasr transcribe input.mp3 --backend faster-whisper
bestasr transcribe input.mp3 --backend whisper.cpp
bestasr transcribe input.mp3 --backend mlx-whisper
```

⸻

### 4.5 指定模型

```
bestasr transcribe input.mp3 --model small
bestasr transcribe input.mp3 --model medium
bestasr transcribe input.mp3 --model large-v3
```

⸻

### 4.6 診斷模式

```
bestasr diagnose
```

⸻

### 4.7 只推薦，不執行

```
bestasr recommend input.mp3
```

輸出：

```json
{
  "backend": "faster-whisper",
  "model": "medium",
  "compute_type": "int8_float16",
  "reason": [
    "CUDA GPU detected",
    "VRAM below 8 GB",
    "medium profile selected",
    "audio language appears multilingual"
  ]
}
```

這個指令很重要，因為它可以讓 bestASR 不只是轉錄工具，而是 ASR model router。

⸻

## 5. 建議 repo 結構

```
bestASR/
  bestasr/
    __init__.py
    cli.py
    detect/
      __init__.py
      system.py
      hardware.py
      acceleration.py
      audio.py
      language.py
    router/
      __init__.py
      rules.py
      scorer.py
      profiles.py
      recommendation.py
    engines/
      __init__.py
      base.py
      faster_whisper_engine.py
      whisper_cpp_engine.py
      mlx_whisper_engine.py
    output/
      __init__.py
      txt.py
      json.py
      srt.py
      vtt.py
    models/
      __init__.py
      registry.py
      requirements.py
    utils/
      __init__.py
      ffmpeg.py
      logging.py
      paths.py
  tests/
    test_hardware_detection.py
    test_router.py
    test_output_formats.py
  examples/
    basic_transcribe.sh
    diagnose.sh
    recommend.sh
  README.md
  pyproject.toml
  LICENSE
```

⸻

## 6. 核心架構

bestASR 可以分成五層：

```
CLI Layer
  ↓
Detection Layer
  ↓
Routing Layer
  ↓
Engine Layer
  ↓
Output Layer
```

⸻

### 6.1 CLI Layer

負責解析使用者指令。

主要檔案：

```
bestasr/cli.py
```

功能：

```
- transcribe
- diagnose
- recommend
- list-backends
- list-models
```

⸻

### 6.2 Detection Layer

負責偵測系統與音訊資訊。

主要檔案：

```
detect/system.py
detect/hardware.py
detect/acceleration.py
detect/audio.py
detect/language.py
```

應該偵測：

```
- OS
- CPU
- RAM
- GPU
- VRAM
- CUDA 是否可用
- Metal 是否可用
- MLX 是否可用
- AVX2 / AVX512 是否可用
- ffmpeg 是否存在
- 音訊長度
- 音訊格式
- sample rate
- channel count
- 語言
```

⸻

### 6.3 Routing Layer

這是 bestASR 的核心。

主要檔案：

```
router/rules.py
router/scorer.py
router/profiles.py
router/recommendation.py
```

它負責決定：

```
- 使用哪個 backend
- 使用哪個模型
- 使用哪種 compute type
- 是否需要降級模型
- 是否需要 fallback
```

⸻

### 6.4 Engine Layer

每個 backend 都包成同樣介面。

主要檔案：

```
engines/base.py
engines/faster_whisper_engine.py
engines/whisper_cpp_engine.py
engines/mlx_whisper_engine.py
```

所有 engine 都應該實作：

```python
class BaseEngine:
    def is_available(self) -> bool:
        ...
    def transcribe(self, audio_path: str, options: TranscribeOptions) -> Transcript:
        ...
    def estimate_requirements(self, model_name: str) -> ModelRequirements:
        ...
```

⸻

### 6.5 Output Layer

負責輸出格式。

主要檔案：

```
output/txt.py
output/json.py
output/srt.py
output/vtt.py
```

支援：

```
- txt
- json
- srt
- vtt
```

⸻

## 7. Router 決策邏輯草案

### 7.1 Profile 權重

```python
PROFILES = {
    "fast": {
        "speed": 0.55,
        "accuracy": 0.20,
        "memory_fit": 0.20,
        "stability": 0.05,
    },
    "balanced": {
        "speed": 0.35,
        "accuracy": 0.35,
        "memory_fit": 0.20,
        "stability": 0.10,
    },
    "accurate": {
        "speed": 0.15,
        "accuracy": 0.60,
        "memory_fit": 0.15,
        "stability": 0.10,
    },
}
```

⸻

### 7.2 候選 backend

第一版支援：

```
faster-whisper
whisper.cpp
mlx-whisper
```

未來可以加入：

```
parakeet
canary
wav2vec2
seamless
cloud-api
```

⸻

### 7.3 簡化決策表

| 環境 | 推薦 backend | 推薦理由 |
|------|-------------|---------|
| Apple Silicon | mlx-whisper | 適合 MLX / Metal |
| NVIDIA GPU + CUDA | faster-whisper | CTranslate2 效能佳 |
| CPU-only | whisper.cpp | quantized model 友善 |
| RAM 很小 | whisper.cpp | 可用較小 quantized 模型 |
| 多語言 | Whisper 系列 | 穩定支援多語言 |
| 英文-only 且追求極速 | 未來可加入 Parakeet | 後續版本 |

⸻

### 7.4 模型選擇邏輯

```
fast:
  - tiny
  - base
  - small
balanced:
  - small
  - medium
accurate:
  - medium
  - large-v3
  - large-v3-turbo
```

⸻

### 7.5 記憶體不足時降級

```
如果模型需求 > 可用記憶體：
  large-v3 → medium
  medium → small
  small → base
  base → tiny
```

⸻

## 8. Recommendation 資料結構

```python
@dataclass
class ASRRecommendation:
    backend: str
    model: str
    compute_type: str
    profile: str
    language: str | None
    estimated_speed: str
    estimated_accuracy: str
    reason: list[str]
    warnings: list[str]
```

範例：

```json
{
  "backend": "mlx-whisper",
  "model": "large-v3-turbo",
  "compute_type": "fp16",
  "profile": "balanced",
  "language": "zh",
  "estimated_speed": "fast",
  "estimated_accuracy": "high",
  "reason": [
    "Apple Silicon detected",
    "MLX backend available",
    "Sufficient unified memory",
    "Chinese transcription requested"
  ],
  "warnings": []
}
```

⸻

## 9. Transcript 資料結構

```python
@dataclass
class TranscriptSegment:
    id: int
    start: float
    end: float
    text: str
    confidence: float | None = None
@dataclass
class Transcript:
    text: str
    language: str | None
    duration: float | None
    segments: list[TranscriptSegment]
    backend: str
    model: str
```

⸻

## 10. README 草案

```markdown
# bestASR
bestASR automatically selects the best local automatic speech recognition model for your machine.
It detects your hardware, operating system, available acceleration backend, memory, audio language, and transcription goal, then chooses the most suitable ASR model and inference engine.
Instead of asking users to decide between Whisper, faster-whisper, whisper.cpp, MLX, CUDA, Metal, fp16, int8, or quantized models, bestASR makes the decision automatically.
## Why bestASR?
Local speech-to-text is powerful, but choosing the right model is confusing.
Should you use Whisper? faster-whisper? whisper.cpp? MLX? CUDA? Metal? fp16? int8? large-v3? turbo? quantized models?
bestASR handles this decision for you.
## Quick start
```bash
pip install bestasr
bestasr transcribe input.mp3
```

### Examples

```
bestasr diagnose
bestasr recommend input.mp3
bestasr transcribe input.mp3 --profile low
bestasr transcribe input.mp3 --profile medium
bestasr transcribe input.mp3 --profile max
bestasr transcribe input.mp3 --format srt
bestasr transcribe input.mp3 --format vtt
```

### Supported backends

* faster-whisper
* whisper.cpp
* mlx-whisper

### Supported output formats

* txt
* json
* srt
* vtt

### Philosophy

bestASR is not another ASR model.

It is an intelligent local ASR router.

Its job is to answer one question:

What is the best speech recognition setup for this machine and this audio file?

⸻

## 11. SDD 用總提示詞草案

你可以把下面這段直接丟給 SDD 工具，作為專案起始 spec。

```text
We are building a Python CLI project named bestASR.
bestASR is an intelligent local ASR model router. It automatically detects the user's hardware, operating system, acceleration backend, memory, audio file properties, language, and transcription goal, then selects the most suitable local automatic speech recognition backend and model.
The project should not train new ASR models. It should orchestrate existing local ASR backends.
Initial supported backends:
1. faster-whisper
2. whisper.cpp
3. mlx-whisper
Initial supported commands:
1. bestasr diagnose
2. bestasr recommend <audio_path>
3. bestasr transcribe <audio_path>
The CLI should support:
- --profile auto|low|medium|high|xhigh|max (effort ladder; renamed from fast/balanced/accurate in #29)
- --backend auto|faster-whisper|whisper.cpp|mlx-whisper
- --model auto|tiny|base|small|medium|large-v3|large-v3-turbo
- --language auto|en|zh|ja|ko|...
- --format txt|json|srt|vtt
- --output <path>
- --explain
The architecture should be modular:
- detect layer: system, hardware, acceleration, audio, language
- router layer: rules, scoring, profiles, recommendation
- engine layer: common BaseEngine interface and backend-specific implementations
- output layer: txt, json, srt, vtt writers
The MVP should prioritize correctness, clear fallback behavior, and explainable recommendations.
The router should first use a rule-based strategy:
- Apple Silicon should prefer mlx-whisper if available.
- NVIDIA CUDA GPU should prefer faster-whisper.
- CPU-only machines should prefer whisper.cpp with quantized models.
- If memory or VRAM is insufficient, downgrade the model size.
- For multilingual transcription, prefer Whisper-family models.
- For low profile, prioritize speed and smaller models.
- For medium profile, prioritize medium-sized models.
- For high/xhigh/max profiles, prioritize larger models when memory allows.
The project should include:
- type hints
- dataclasses or pydantic models for recommendations and transcripts
- unit tests for hardware detection, router decisions, and output writers
- graceful error handling when a backend is not installed
- clear installation instructions
- a README with examples
Please generate a full implementation plan, break the project into milestones, define file structure, define interfaces, and produce implementation tasks in order.
```

⸻

## 12. SDD 分階段開發建議

我建議你不要讓 SDD 一次生成整個專案。比較穩的方式是拆成 6 個階段。

### Phase 1：專案骨架

目標：

建立 pyproject.toml、CLI、基本資料結構、測試框架。

完成後應該可以跑：

```
bestasr --help
bestasr diagnose
```

但 diagnose 可以先回傳 mock 資料。

⸻

### Phase 2：硬體與系統偵測

目標：

實作 OS、CPU、RAM、GPU、CUDA、Apple Silicon、Metal、MLX、ffmpeg 偵測。

完成後：

```
bestasr diagnose
```

要能真的輸出目前電腦狀態。

⸻

### Phase 3：Router

目標：

實作 rule-based recommendation。

完成後：

```
bestasr recommend input.mp3
```

要能輸出推薦 backend、model、compute type、reason。

這一階段是整個專案最重要的部分。

⸻

### Phase 4：Output writers

目標：

支援 txt、json、srt、vtt。

這階段不需要真的轉錄，可以用假 transcript 測試輸出格式。

⸻

### Phase 5：Engine integration

目標：

接上 faster-whisper、whisper.cpp、mlx-whisper。

建議順序：

1. faster-whisper
2. whisper.cpp
3. mlx-whisper

⸻

### Phase 6：穩定化與 README

目標：

補測試、補錯誤訊息、補 README、補 examples。

⸻

## 13. 我建議第一個 issue 這樣寫

```markdown
# Issue 1: Create bestASR project skeleton
## Goal
Create the initial Python package structure for bestASR.
## Requirements
- Use Python 3.10+
- Use pyproject.toml
- Provide a CLI entry point named `bestasr`
- Implement these commands:
  - `bestasr diagnose`
  - `bestasr recommend <audio_path>`
  - `bestasr transcribe <audio_path>`
- Commands may return placeholder data in this issue.
- Add initial dataclasses:
  - SystemInfo
  - AudioInfo
  - ASRRecommendation
  - Transcript
  - TranscriptSegment
- Add basic unit tests.
- Add README.md with project description.
## Acceptance Criteria
- `bestasr --help` works
- `bestasr diagnose` works
- `bestasr recommend sample.mp3` returns a JSON-like recommendation
- `pytest` passes
```

⸻

## 14. 專案真正的護城河

bestASR 的價值不是支援很多模型，而是這三件事：

1. 推薦準確
2. fallback 穩定
3. 解釋清楚

所以 README 裡面一定要強調：

bestASR does not just run transcription.
It explains why a model was selected.

也就是說，bestASR 應該要像這樣：

不要只說：
Using medium model.
而是說：
Using faster-whisper medium int8_float16 because CUDA is available but VRAM is below 8 GB.

這樣它會比一般 CLI 工具更有辨識度。

⸻

## 15. 我會建議的最終定位

bestASR is the intelligent model router for local speech recognition.

中文可以寫：

bestASR 是本機語音辨識模型的智慧路由器。

這個定位很準，而且未來可以擴充到：

```
- 逐字稿
- 字幕
- 語言偵測
- 即時轉錄
- 說話者分離
- benchmark
- 模型推薦
- 桌面 app
- server API
```

但第一版先把 diagnose + recommend + transcribe 做好就夠了。
