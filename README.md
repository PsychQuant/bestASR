# bestASR

**The benchmark-driven local ASR router for Apple Silicon.**

bestASR measures how speech-recognition backends and models *actually perform
on your machine* — then recommends and runs the best setup, and explains why.

Instead of guessing between WhisperKit, whisper.cpp, model sizes, and
quantization levels, you benchmark them once against your own audio and a
ground-truth `.srt`, and every later `recommend` / `transcribe` is backed by
real numbers:

> Not: `Using medium model.`
> But: `whisperkit large-v3-turbo — measured on this machine: CER 5.0%, 12.0x realtime.`

## Why bestASR?

Local speech-to-text on a Mac has real choices with real trade-offs:
WhisperKit rides CoreML and the Neural Engine; whisper.cpp brings flexible
GGML quantization. Which is *best* depends on your machine, your audio, your
language, and whether you care more about accuracy or speed.

"Best" should not be a guess. bestASR's moat is three things: **measured
recommendations**, **stable fallback**, and **clear explanations**.

## Requirements

- Apple Silicon Mac (arm64) — Intel Macs and Rosetta are not supported
- macOS 14 (Sonoma) or later

## Install

```bash
git clone https://github.com/PsychQuant/bestASR.git
cd bestASR
swift build -c release
cp .build/release/bestasr /usr/local/bin/  # or anywhere on PATH
```

Backends:

- **WhisperKit** is built in — models download on demand at first use.
- **whisper.cpp** is optional: `brew install whisper-cpp`, then place GGML
  model files under `~/.bestasr/models/whisper-cpp/` (the error message tells
  you the exact file name and download URL when one is missing). Quantization
  variants differ per model on HuggingFace — `bestasr list-models` shows the
  hosted set (e.g. tiny/base/small ship `q5_1`, not `q5_0`).

## Quick start

```bash
bestasr diagnose                 # what is this machine, and what would it recommend?
bestasr transcribe input.mp3     # transcribe with the best known setup
```

### The benchmark workflow (where "best" gets real)

```bash
# 1. Measure every available backend/model/quantization against ground truth
bestasr benchmark clip.wav --reference clip.srt --language zh

# 2. From now on, recommendations cite your machine's measured numbers
bestasr recommend clip2.wav --language zh
# → "data_source": "measured", CER + x-realtime from YOUR benchmark

# 3. Transcribe with the winner — and see why it won
bestasr transcribe clip2.wav --language zh --explain
```

The ground truth is a standard `.srt` subtitle file. Accuracy is scored as
**CER** for languages without word spacing (zh / ja / ko) and **WER**
otherwise; speed as measured times-realtime (model download/load excluded);
results persist in `~/.bestasr/benchmarks.json` per machine.

### Context calibration (make domain terms and names come out right)

Put your documents into a context folder and bestASR biases the decoder toward
your vocabulary — and an agent can proofread the result:

```bash
# 1. Distill documents (pdf/docx/…) into context.json — agent skill
claude plugin marketplace add PsychQuant/bestASR
#    then ask Claude to run the context-ingest skill on your docs folder

# 2. Transcribe with context (auto-resolves --context-dir >
#    ./bestasr-context/ > ~/.bestasr/context/) and see what got injected
bestasr transcribe input.mp3 --explain

# 3. Prove the biasing works on YOUR audio (± context delta columns)
bestasr benchmark clip.wav --reference clip.srt --context-dir ./bestasr-context

# 4. Agent-side proofreading (three-axis: speaker / timestamp / text,
#    timecodes immutable) — srt-proofread skill
```

`context.json` v1 carries `terms`, `names` (with aliases + roles — the speaker
axis), and `phrases`; plain `.txt`/`.md` term lists work too. Unsupported
formats are loudly ignored with guidance. An empty folder changes nothing.

### Commands

| Command | What it does |
|---------|--------------|
| `bestasr diagnose` | Hardware profile (chip / unified memory / ANE / macOS) + recommendation |
| `bestasr benchmark <audio> --reference <gt.srt>` | Measure candidates, print ranked table, persist results (`--json` for machines) |
| `bestasr recommend <audio>` | JSON recommendation only — measured when data exists, cold-start prior otherwise |
| `bestasr transcribe <audio>` | Transcribe; `--format txt\|json\|srt\|vtt`, `--output`, `--context-dir`, `--explain` |
| `bestasr list-backends` | Backend availability on this machine |
| `bestasr list-models` | Model sizes and quantization variants |

Shared selection flags: `--profile fast|balanced|accurate`, `--backend`,
`--model`, `--language`.

## How it works

```
CLI → Detect (chip/memory/ANE, AVFoundation audio probing)
    → Route  (tier 1: rank measured benchmark records for this chip;
              tier 2: cold-start prior + memory downgrade — and it tells you
              to benchmark)
    → Engine (WhisperKit · whisper.cpp, one normalized interface)
    → Output (txt / json / srt / vtt)
```

Every recommendation carries a `reason` list. Cold-start recommendations say
so honestly and point you at `bestasr benchmark`.

## Development

```bash
swift test          # 95+ tests, no real models needed (engines are mocked)
swift build         # debug build
```

Specs live in `openspec/specs/` (Spectra spec-driven development). The
original cross-platform Python implementation is preserved under
`archive/python/` for reference.

## License

MIT
