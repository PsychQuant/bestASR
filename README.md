# bestASR

**The intelligent model router for local speech recognition.**

bestASR automatically selects the best local automatic speech recognition setup
for your machine. It detects your hardware, operating system, available
acceleration backend, memory, audio properties, and language, then chooses the
most suitable ASR **backend**, **model**, and **compute type** — and explains
why.

Instead of asking you to decide between Whisper, faster-whisper, whisper.cpp,
MLX, CUDA, Metal, fp16, int8, `large-v3`, turbo, or quantized models, bestASR
makes the decision for you.

> bestASR does not just run transcription. It explains *why* a model was chosen.
>
> Not: `Using medium model.`
> But: `Using faster-whisper medium int8_float16 because CUDA is available but VRAM is below 8 GB.`

## Why bestASR?

Local speech-to-text is powerful, but choosing the right model is confusing.
Should you use Whisper? faster-whisper? whisper.cpp? MLX? CUDA? Metal? fp16?
int8? `large-v3`? turbo? bestASR handles this decision — and, crucially, tells
you the reasoning so you can trust or override it.

Its moat is three things: **accurate recommendations**, **stable fallback**, and
**clear explanations**.

## Install

```bash
pip install bestasr
```

Backends are optional and platform-specific — install what fits your machine:

```bash
pip install "bestasr[faster-whisper]"   # NVIDIA CUDA / CPU
pip install "bestasr[mlx]"              # Apple Silicon (Metal / MLX)
pip install "bestasr[whispercpp]"       # quantized CPU
```

If no backend is installed, `bestasr diagnose` still reports your environment
and tells you exactly what to install.

## Quick start

```bash
bestasr diagnose                 # what's my machine, and what does it recommend?
bestasr recommend input.mp3      # print a JSON recommendation, no transcription
bestasr transcribe input.mp3     # transcribe using the auto-chosen setup
```

### Choose a profile

```bash
bestasr transcribe input.mp3 --profile fast       # prioritize speed
bestasr transcribe input.mp3 --profile balanced   # default
bestasr transcribe input.mp3 --profile accurate   # prioritize accuracy
```

### Output formats

```bash
bestasr transcribe input.mp3 --format srt
bestasr transcribe input.mp3 --format vtt
bestasr transcribe input.mp3 --format json
bestasr transcribe input.mp3 --output transcript.txt
```

### See the reasoning

```bash
bestasr transcribe input.mp3 --explain
```

### Override the automatic choice

```bash
bestasr transcribe input.mp3 --backend faster-whisper --model medium --language zh
```

## How it works

bestASR is a five-layer pipeline:

```
CLI  →  Detection  →  Routing  →  Engine  →  Output
```

- **Detection** — OS, CPU, RAM, GPU/VRAM, CUDA/Metal/MLX, ffmpeg, and audio properties.
- **Routing** — a rule-based decision table picks a backend (Apple Silicon → MLX,
  CUDA → faster-whisper, CPU → whisper.cpp), then a profile picks the model and
  compute type, downgrading if memory is tight and falling back if a backend is
  missing. Every choice records a reason.
- **Engine** — a common interface over faster-whisper, whisper.cpp, and mlx-whisper.
- **Output** — txt, json, srt, vtt.

## Supported backends

- `faster-whisper`
- `whisper.cpp`
- `mlx-whisper`

## Supported output formats

- `txt`, `json`, `srt`, `vtt`

## Philosophy

bestASR is not another ASR model. It is an intelligent local ASR router whose
job is to answer one question:

> What is the best speech recognition setup for this machine and this audio file?

## Development

```bash
pip install -e ".[dev]"
pytest
```

## License

MIT
