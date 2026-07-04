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
- The model grid additionally carries a **reference catalog** of 15
  MLX-native STT families (Parakeet, Qwen3-ASR, Moonshine, Canary, MMS,
  Voxtral, …) with verified HuggingFace repos and pinned revisions — visible
  in `bestasr list-models` for lookup. No engine is bundled for them (the
  mlx-audio backend was evaluated and removed (#20); git history has the
  full implementation if it's ever wanted back).

## Quick start

```bash
bestasr diagnose                            # what is this machine, and what would it recommend?
bestasr transcribe input.mp3                # best known setup, chosen for you
bestasr transcribe input.mp3 --profile max  # most accurate, time is no object
```

With no flags, bestASR decides for you — that's the point. The default
profile is `auto`: it reads your hardware (chip, unified memory, Neural
Engine), your measured benchmark store, **and the machine's current
condition** — under thermal pressure or Low Power Mode, `auto` downshifts to
a faster tier rather than grinding a hot machine through a huge model, and
`--explain` tells you it did.

### Effort profiles

`--profile` is an ordinal effort ladder (modeled on Claude Code's effort
levels): pick how hard the router should chase accuracy, and it maps that to
concrete models using your machine's measured numbers.

| Profile | Accuracy : speed weighting | What it means |
|---------|---------------------------|---------------|
| `auto` *(default)* | — | `medium` normally; `low` when the machine reports pressure (thermal serious/critical, or Low Power Mode). Never applied on top of an explicit choice. |
| `low` | 0.267 : 0.733 | Fastest acceptable — drafts, long batch queues |
| `medium` | 0.5 : 0.5 | The balanced default |
| `high` | 0.8 : 0.2 | Accuracy-leaning, still speed-aware |
| `xhigh` | 0.9 : 0.1 | Near-max accuracy |
| `max` | 1.0 : 0 | **Most accurate regardless of time.** A pure argmax over measured error rate; equal-accuracy ties break to the faster candidate |

"Most accurate" means *measured on your machine* whenever benchmark data
exists — not a hardcoded model name. Without measurements the top tiers fall
back to the same biggest-that-fits cold-start prior (ordinals can only
differ once there is data to weigh — run the benchmark).

Because `auto` reads live machine state, `recommend` / `transcribe` with no
`--profile` can resolve differently on a throttled machine (it says so in
`--explain`). If you need a byte-stable result for automation, pass an
explicit ordinal — an explicit choice is never touched by machine state.

Migrating from ≤0.7.x: `fast` → `low`, `balanced` → `medium`, `accurate` →
`high` (or `max` when you truly don't care about time). The old names now
fail with exactly that hint.

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

Register your ground truth once (`bestasr corpus add talk.wav talk.srt
--language zh`; `scripts/fetch-corpora.sh` fetches the English standard set)
— results land in the BCNF store at `~/.bestasr/store/` (four JSONL tables;
measurements are append-only, routing reads the latest per model × corpus ×
machine). The ground truth is a standard `.srt` subtitle file. Accuracy is scored as
**CER** for languages without word spacing (zh / ja / ko) and **WER**
otherwise; speed as measured times-realtime (model download/load excluded —
WhisperKit pipelines load once per model and are reused, so its timed pass
measures pure decode speed; whisper.cpp runs as a subprocess and its timed
pass includes a small GGML load); results persist in
`~/.bestasr/benchmarks.json` per machine.

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

### Speaker diarization (who spoke when)

```bash
bestasr transcribe meeting.m4a --format srt --diarize
```

```
1
00:00:00,000 --> 00:00:09,300
[SPEAKER_1] 先講一下上週的進度……

2
00:00:10,300 --> 00:00:18,000
[SPEAKER_2] 我這邊模型已經跑完了。
```

Each cue is labeled with the acoustic speaker that overlaps it most.
Speakers are numbered in order of first appearance; CoreML diarization
models download on first use. Works with every output format (`srt` / `vtt`
/ `txt` / `json`).

### Speaker identification (who is SPEAKER_1, actually)

Drop a short voice sample per person into a `voices/` folder inside your
context directory — the filename becomes the label:

```
bestasr-context/
  context.json
  voices/
    Alice.wav      # a few seconds of Alice speaking, alone
    Bob.m4a
```

```bash
bestasr transcribe meeting.m4a --format srt --diarize
# → [Alice] …, [Bob] …, and any un-enrolled voice stays [SPEAKER_1]
```

Identification is a post-hoc embedding match against each recording's
diarized speakers (cosine distance, 0.65 threshold): enrolled voices are
labeled by name, strangers keep their ordinals, and a corrupt sample is
skipped with a warning instead of failing the transcription.

**Voice prints are sensitive biometric data — bestASR ships no code that
transmits them.** Concretely: `voices/` is in the repo's `.gitignore`, the
context-ingest skill's rules exclude it, and the only reader is the local
`--diarize` run. (These are the enforced mechanisms; bestASR cannot govern
what other tools on your machine do with the files.)

### Transcribe any source (agent skill)

`bestasr transcribe` takes a local audio file. The **`transcript` agent skill**
(in this repo's Claude plugin) wraps it so you can point at *any* source —
a YouTube URL, any yt-dlp-supported site, a local audio/video file, or an
existing subtitle — and get an SRT back:

```
transcript https://www.youtube.com/watch?v=xxxx      # download audio → ASR → SRT
transcript ~/Movies/lecture.mp4 --profile max        # local video, most accurate
transcript ~/rec/meeting.m4a --context-dir ./bestasr-context --diarize
transcript                                           # no source → the skill asks
```

The skill treats every input as a "source" and branches by type: URLs and
video get their audio extracted (yt-dlp / ffmpeg) then ASR-transcribed;
audio files go straight to `bestasr transcribe`; an existing `.srt`/`.vtt` is
normalized rather than re-transcribed. Downloaded audio lives in a temp dir
and is always cleaned up. This is **ASR transcription** — distinct from
grabbing a platform's existing captions (that's a different tool).

### See why (--explain)

Every selection is explainable — including what `auto` decided:

```
Selected whisperkit large-v3-turbo [measured] because:
  - auto profile resolved to medium (no machine pressure)
  - measured on this machine: CER 5.0%, 12.0x realtime
  - whisperkit preferred on Apple Silicon (CoreML path)
```

Under load the first line becomes
`auto profile downshifted to low (thermal state: serious)` — no silent
behavior changes.

### Commands

| Command | What it does |
|---------|--------------|
| `bestasr diagnose` | Hardware profile (chip / unified memory / ANE / macOS) + recommendation |
| `bestasr benchmark <audio> --reference <gt.srt>` | Measure candidates, print ranked table, persist results (`--json` for machines) |
| `bestasr recommend <audio>` | JSON recommendation only — measured when data exists, cold-start prior otherwise |
| `bestasr transcribe <audio>` | Transcribe; `--format txt\|json\|srt\|vtt`, `--output`, `--context-dir`, `--diarize`, `--explain` |
| `bestasr list-backends` | Backend availability on this machine |
| `bestasr list-models` | The model grid: whisper sizes + the 15-family mlx-audio catalog with priority tiers |
| `bestasr corpus add <audio> <ref.srt> --language <l>` | Register ground truth (zh/ja: bring your own material) |
| `bestasr corpus list` | Registered corpora |

Shared selection flags: `--profile auto|low|medium|high|xhigh|max`,
`--backend auto|whisperkit|whisper.cpp`, `--model`, `--language`.

## How it works

```
CLI → Detect (chip/memory/ANE, AVFoundation audio probing,
              dynamic machine state: thermal + Low Power Mode)
    → Route  (tier 1: rank measured benchmark records for this chip;
              tier 2: cold-start prior + memory downgrade — and it tells you
              to benchmark)
    → Engine (WhisperKit · whisper.cpp, one normalized interface)
    → Output (txt / json / srt / vtt, optional speaker labels)
```

Every recommendation carries a `reason` list. Cold-start recommendations say
so honestly and point you at `bestasr benchmark`.

## Development

```bash
swift test          # 200+ tests, no real models needed (engines are mocked)
swift build         # debug build
```

Specs live in `openspec/specs/` (Spectra spec-driven development). The
original cross-platform Python implementation is preserved under
`archive/python/` for reference.

## License

MIT
