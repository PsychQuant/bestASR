# Changelog

All notable changes to bestASR are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

## [0.5.0] - 2026-07-03

### Added

- **zh/ja standard corpora (#18)** — `scripts/fetch-corpora.sh` builds Mandarin and
  Japanese benchmark corpora from FLEURS (google/fleurs, CC-BY-4.0, ungated): three
  distinct dev-split utterances per language, converted from float32 to 16 kHz mono
  int16 and concatenated (~30s zh / ~38s ja) with verbatim SRT references embedded and
  a CC-BY attribution NOTICE emitted beside the artifacts. Supply chain pinned end to
  end per the #15 discipline (dataset revision, raw tar digest verified before any
  parser touches the bytes, converted artifact verified before it reaches its final
  path); per-corpus isolation means one failed download can no longer block the
  others. With these registered, `recommend --language zh|ja` answers from measured
  data instead of cold-start.
- **Pin provenance on measurements (#16)** — each appended measurement records
  `hf_revision` resolved from the models table *as seeded for that run* (the catalog is
  rewritten wholesale on every seed, so a pin bump used to silently re-associate
  historical numbers with the new snapshot — #15 verify's find). Audit-only optional
  column: legacy rows decode `nil`; projection and routing untouched.

### Changed

- **Store rewrites preserve unparseable lines (#16)** — `upsert(corpus:)` and wholesale
  model seeding previously kept only the rows they could parse, silently deleting a
  malformed line that load had merely warned about. `rewrite()` now appends undecodable
  lines back verbatim (byte-level, so non-UTF-8 corruption survives too), so they keep
  surfacing the load warning instead of vanishing — the "corrupt rows degrade loudly,
  not fatally" contract now covers the rewrite path.

## [0.4.0] - 2026-07-02

### Removed

- **mlx-audio backend** (#20): the third backend (engine, JSON-lines worker,
  venv probe, router pairing) is removed by owner decision — its integration
  cost (Python venv, worker lifecycle, fast-moving upstream API; see the
  #14/#15 verify rounds) exceeded the need. The 15-family model catalog
  stays in the grid as a **reference** (families, verified HF repos, pinned
  revisions, historical priority tiers) shown by `list-models`; stored
  measurements remain (append-only) and are silently filtered from routing.
  Reinstatement is a git revert away.

## [0.3.1] — 2026-07-02

### Security

- **Supply-chain pinning** (#15): the English corpus fetch script verifies the
  raw third-party download against a pinned digest BEFORE any parser touches
  it, and verified mlx-audio grid rows pin their HF repo to a commit sha —
  the worker resolves the pinned snapshot via huggingface_hub and loads the
  immutable local path through mlx-audio (with explicit model-type dispatch,
  since snapshot dir names are bare shas). Bumping a pin implies re-verifying.

## [0.3.0] — 2026-07-02

### Added

- **mlx-audio third backend** (#14): MLX-native STT families via a persistent
  JSON-lines Python worker per model (dedicated uv venv; model load lands in
  the warm-up pass, timed pass measures pure inference). Models are addressed
  as `family/size` (e.g. `parakeet/0.6b`).
- **Model grid** (#14): full-family catalog (15 mlx-audio families + the
  whisper backends) with priority tiers — the default benchmark sweep runs
  priority-1 rows; `--all-grid` widens. Unverified HF repos are marked and
  never turned into guessed URLs.
- **BCNF benchmark store** (#14): `~/.bestasr/store/` holds four JSONL tables
  (machines / models / corpora / measurements) with append-only measurements
  and a latest-per-(model, corpus, machine) projection; the legacy
  `benchmarks.json` migrates once and gains a `.bak` suffix.
- **Verify-round hardening** (#14 6-AI findings): mlx-audio cold-start pairs
  correctly (`--backend mlx-audio` picks from its own grid; bare
  `--model family/size` infers the backend); explain honestly discloses that
  mlx-audio cannot use the context prompt instead of implying injection;
  benchmark no longer clobbers registered corpus name/language; routing
  projection aggregates one record per candidate (legacy ids converge, order
  deterministic); worker responses correlate by id and dead workers are
  evicted; the venv probe is memoized out of the timed pass.
- **Grid-aware model addressing** (#14): `family/size` names validate through
  the router, resolve memory estimates from their grid rows, and only pair
  with backends whose grid lists variants (a clean usage error instead of a
  crash for incompatible pairs); the availability chain includes mlx-audio.
  Note: the mlx whisper row points at `openai/whisper-large-v3-turbo` — the
  mlx-community conversions ship no `preprocessor_config.json` and fail
  mlx_audio's whisper loader (live-probed 2026-07-02).

## [0.2.1] — 2026-07-02

### Changed

- **BestASRKit API (deliberate pre-1.0 break)**: `ModelRegistry.quantizations`
  dictionary is replaced by `quantizations(for:model:)`, and
  `defaultQuantization(for:)` now requires a `model:` parameter. No
  deprecation shims - the package has no tagged releases or external
  consumers yet.

### Added

- **Pipeline seam for wiring-level tests** (#9): `TranscribingPipeline`
  protocol + injectable pipeline factory on `WhisperKitEngine`, so tests can
  spy on the `DecodingOptions` the engine actually sends (locking the #6
  `skipSpecialTokens` fix at the production path, not just the factory
  function). The pipeline cache is now engine-instance-scoped.

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

- **WhisperKit pipelines load once per model and are reused** (#7): a
  process-lifetime create-once cache (with keep-current eviction, so a full
  benchmark sweep keeps the old one-model-at-a-time memory envelope) backs
  the engine; the timed benchmark pass now measures pure decode speed as the
  benchmark spec requires. Measured on OSR Harvard (M5 Max): WhisperKit tiny
  X-REAL 6.8x → 114.2x, base 6.6x → 76.5x, WER unchanged. peak-GB is
  sampled before warm-up so it keeps the model footprint for in-process
  backends (subprocess backends under-report; the report footnote says so).

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
