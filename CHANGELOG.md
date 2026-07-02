# Changelog

All notable changes to bestASR are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

### Fixed

- **whisper.cpp quantization table is now per-model and HF-accurate** (#5):
  tiny/base/small offer `q5_1`/`q8_0`, medium/large-v3-turbo offer
  `q5_0`/`q8_0`, and large-v3 offers `q5_0` only — matching the actual
  `ggerganov/whisper.cpp` HuggingFace distribution. Previously a flat
  `q5_0`/`q8_0` list applied to every model, so the model-missing error
  pointed small models at a 404 download URL and `benchmark` enumerated
  candidates that could never succeed. `list-models` now prints the
  per-model variants; cold-start recommendations default to the first
  (hosted) variant.
- **WhisperKit transcripts no longer contain special tokens** (#6):
  `skipSpecialTokens` is now always set, so `<|startoftranscript|>` /
  timestamp tokens stay out of transcripts and WER. Real-file measurements
  (whisper.cpp canonical `jfk.wav`, OSR Harvard List 1): jfk WhisperKit
  tiny/base 9.1%/13.6% → **0.0%/0.0%**; OSR 30.0%→17.5%, 26.2%→12.5%.

### Known issues

- WhisperKit rebuilds its pipeline on every call, so its X-REAL figures
  reflect per-invocation latency rather than sustained decode speed (#7).

## [0.2.0] — 2026-07-02

### Added

- Context calibration (#3): three-layer context-folder resolution
  (`--context-dir` > `./bestasr-context/` > `~/.bestasr/context/`),
  `context.json` v1 (terms / names+aliases+roles / phrases), plain-text term
  lists, natural-language prompt biasing with a ~200-token budget and
  names→terms→phrases truncation priority, `--explain` disclosure, and
  `benchmark --context-dir` ±context delta columns.
- Claude plugin marketplace (#4): `claude plugin marketplace add
  PsychQuant/bestASR` ships the `bestasr` plugin with two skills —
  `context-ingest` (documents → context.json) and `srt-proofread`
  (three-axis SRT correction with immutable timecodes).

## [0.1.0] — 2026-07-01

### Added

- Swift-native, Apple-Silicon-first CLI: `diagnose` / `benchmark` /
  `recommend` / `transcribe` / `list-backends` / `list-models`.
- Benchmark-driven routing: measured records (CER/WER + times-realtime,
  warm-up excluded) persist per machine in `~/.bestasr/benchmarks.json`;
  cold-start prior with honest "benchmark me" guidance otherwise.
- Backends: WhisperKit (CoreML/ANE) built in; whisper.cpp via `whisper-cli`
  subprocess with GGML models under `~/.bestasr/models/whisper-cpp/`.
- The original cross-platform Python MVP is preserved under `archive/python/`.
