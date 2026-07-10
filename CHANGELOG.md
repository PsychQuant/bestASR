# Changelog

All notable changes to bestASR are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

## [0.12.0] - 2026-07-10

### Added

- **MCP async job mode (#86)**: `transcribe` accepts an opt-in `async` flag and
  returns a `job_id` immediately; new read-only tools `transcribe_status` and
  `transcribe_result` (bounded long-poll, 25 s cap) poll it. Jobs live in a
  bounded in-memory registry (TTL eviction + a global sweep on every start) and
  share the same single-flight serialization as synchronous transcribes.
- **macOS GUI dual-track bundle (#87)**: new SwiftUI `bestasr-gui` app (drag &
  drop / file picker, language/effort/format pickers persisted across launches,
  honest stage+elapsed progress, transcript preview + reveal-in-Finder) and
  `scripts/release-app.sh`, which assembles, signs, notarizes, and **staples**
  a `bestASR.app` carrying the GUI, `bestasr-mcp`, and the CLI as
  `bestasr-cli` (default APFS is case-insensitive — a `bestasr` entry would
  overwrite the `bestASR` GUI executable). First offline-Gatekeeper-verifiable
  bestASR artifact, published as `bestASR-0.12.0.zip` on the v0.12.0 release.
- **LibriSpeech English benchmark corpora (#88)**: test-clean + dev-clean,
  8 corpora / 48 utterances, source tarballs and converted artifacts digest-
  pinned end to end; `references/asr-benchmark-landscape.md` records the cited
  dataset/license/methodology survey behind the pick.

### Fixed

- **External-adapter watchdog hang (#91)**: a spurious `Process.isRunning`
  false right after launch could skip the timeout watchdog entirely, leaving an
  unbounded `waitUntilExit()` (a 1-hour CI hang). The loop is now gated on a
  `terminationHandler`-driven exit latch installed before `run()`, so it can
  exit only via real process exit or the SIGTERM→SIGKILL deadline branch.
- **bash 3.2 empty-array crash in release/install scripts**: expanding an empty
  `"${BUILD_ENV[@]}"` under `set -u` aborts on stock macOS bash — which killed
  the build exactly on the recommended Xcode-toolchain path. Guarded in
  `release-app.sh`, `release-mcp.sh`, and `install.sh`; the app version parse
  is now scoped to the `BestASRVersion` enum and semver-asserted.

## [0.11.0] - 2026-07-08

### Added

- **MCP server surface (#80, #84)**: `bestasr-mcp` speaks MCP over stdio
  (official swift-sdk), linking BestASRKit directly so engine pipeline caches
  persist across tool calls; v1 tools: transcribe / recommend / list_backends /
  list_models / corpus_add. Tool errors are loud and typed; transcribes are
  single-flight serialized.
- **Plugin bundles the MCP server (#85)**: the Claude Code plugin auto-downloads
  a Developer ID-signed, notarized `bestasr-mcp` from GitHub Releases
  (che-mcps wrapper pattern); `scripts/release-mcp.sh` builds, signs,
  smoke-tests under hardened runtime, notarizes, and publishes it.

### Added
- mlx-audio catalog measured (#65): seven families live-probed, revision-pinned, and benchmarked — canary 1b / granite-speech 2b / voxtral-realtime 4b hit en WER 3.8% (front-tier), vibevoice-asr 9b reaches zh CER 17.7%; nemotron-asr and moonshine verified; qwen2-audio measured (chat-style output inflates WER honestly). qwen3-asr and mega-asr fail in the mlx_audio loader ("All arrays must have the same shape"); distil-whisper lacks its processor config; mms / voxtral mini-3b / qwen3-forcedaligner have no mlx conversion. mlx candidates are now addressed family/size end-to-end (bare-size collision trapped the benchmark report).

### Fixed
- Routing no longer recommends pathological candidates (#64): measured records now aggregate per candidate (equal-weight mean error rate / realtime factor) before ranking, a mean error rate above 0.5 is excluded from autonomous recommendation (explicit backend locks bypass with a warning), and single-measurement winners carry a coverage warning.

### Added
- External-process engine protocol (#51): versioned JSON over argv spawn, `~/.bestasr/engines.json` registry, and a bundled mlx-audio adapter (own venv) that upgrades the 15-family reference catalog to runnable candidates. One process per call, hard timeout, loud attributed failures; external RTF includes full process lifetime.
- Chinese ASR families (#50): `fluid-sensevoice` (SenseVoice small — zh-TW mean CER 0.1941, near whisper-large parity at ~6x realtime) and `fluid-paraformer` (wired, shelved at priority 2 — FluidAudio 0.15.4 decode bug emits raw BPE subwords). Zero new dependencies; text-only families yield a single full-duration segment.
- FluidAudio model weights are now digest-pinned: `WeightVerifier` checks every downloaded file against `weights-manifest.json` before first use (pinned mismatch fails loudly; unpinned models warn — TOFU). `scripts/pin-weights.sh` regenerates the manifest. (#52)
- Benchmark SRT references now strip recurring speaker-label prefixes (`Name: `) when deriving ground-truth text, so speaker-labeled transcripts (e.g. panel recordings) no longer inflate WER; one-off colon phrases stay verbatim. First long-form conversational English corpus (Jobs & Gates D5 2007, 81 min) registered via `corpus add`. (#55)

### Changed
- **Breaking (output format)**: diarized speaker prefixes are now human-readable — SRT/VTT cues read `Speaker 1: text` (was `[SPEAKER_1] text`) and txt lines use the same `Speaker N: ` form; enrolled names render as `Name: `. JSON keeps the internal `SPEAKER_N` label. Downstream parsers of the old bracket form must update. (#54)

## [0.10.0] - 2026-07-06

### Added

- **Three-language regression benchmark suite (#34)**: the standard corpora
  are now en / **Traditional Chinese** / ja, ~20-30 utterances per language in
  3-5 medium corpora each, fully digest-pinned. The Chinese set is Common
  Voice zh-TW (CC-0, Taiwanese Mandarin) via a pinned HF mirror revision —
  **the Simplified FLEURS `cmn_hans_cn` corpus is removed**; "Chinese" in this
  project means Traditional Chinese. ja scales to 24 FLEURS utterances; en
  gains OSR Harvard Lists 2-3 (ASR-verified against the canonical texts).
- **Accuracy-only regression gate**: `benchmarks/baseline.json` pins
  golden CER/WER per corpus for the fixed reference model
  (whisperkit large-v3-turbo); `scripts/regression-gate.sh` re-benchmarks and
  fails loudly on any regression past tolerance. Speed is machine-dependent
  and never gated; seeding provenance (machine, model-repo revision at
  seeding) is recorded in `benchmarks/baseline-meta.json` for drift triage.
  Live-proven: all 12 corpora reproduce their goldens to ±0.0000 on a repeat
  run on the seeding machine; a sabotaged golden fails with the corpus named.

### Fixed

- **Traditional-Chinese CER no longer punishes output script (#34)**:
  Whisper-family models emit Simplified for Mandarin, so a Traditional
  reference scored CER 0.35-0.48 on nearly-correct output. Chinese CER (any
  zh tag — `zh`, `zh-TW`, `zh-Hant`, … via the shared base-subtag predicate)
  now folds both sides Traditional→Simplified (system ICU transform) inside
  metric computation only — delivered transcripts are untouched, Japanese
  kanji and `auto` are never folded, and the zh goldens dropped to their
  honest 0.09-0.16.
- **Regression-gate hardening (#34 verify)**: benchmark output and baseline
  JSON now reach python as files/argv/stdin only (never spliced into python
  source); benchmark runs read `/dev/null` so a stdin-reading subprocess
  can't swallow the work list; corpus names are validated before touching the
  filesystem; duplicate corpus entries and an empty baseline are explicit
  gate errors; standard corpora on disk with no baseline entry fail the gate
  instead of being silently skipped.
- **Deterministic canary decode (#34 verify)**: live verification caught
  Whisper's temperature fallback flipping cv-zhtw-4's CER between runs —
  stochastic sampling under the gate's "same audio → same number" premise.
  A controlled A/B pinned the direction: first-pass greedy is 0.1452 (3/3
  identical), while the default fallback usually re-decodes it to a *worse*
  0.2097 and occasionally back. `bestasr benchmark` gains
  `--decode-deterministic` (WhisperKit `temperatureFallbackCount=0`,
  whisper-cli `-nf`) and the gate uses it; cv-zhtw-4's golden was re-seeded
  0.2097 → 0.1452 (the old value was a fallback artifact — the other 11
  corpora never trip fallback and kept their goldens). Normal transcription
  keeps the fallback rescue.

## [0.9.0] - 2026-07-04

### Added

- **`transcript` agent skill** (#31): a conversational bestASR plugin skill that
  takes any source — a YouTube (or any yt-dlp-supported) URL, a local
  audio/video file, or an existing subtitle — and produces an SRT. Download
  lives in the skill orchestration layer (yt-dlp/ffmpeg extract audio →
  `bestasr transcribe --format srt`), keeping the CLI a pure local ASR router.
  Every input is a "source" branched by type (URL/video extract audio then ASR;
  audio transcribes directly; an existing `.srt`/`.vtt` is normalized, not
  re-transcribed); an empty invocation asks for a source. Pasted URLs/paths are
  validated as untrusted input before reaching any shell command, and the whole
  download→transcribe→output pipeline runs in a single shell so the temp audio
  is never orphaned.

## [0.8.0] - 2026-07-04

### Changed

- **`--profile` becomes an ordinal effort ladder — `low` / `medium` / `high` /
  `xhigh` / `max` — with a machine-aware `auto` default** (#29). Modeled on
  Claude Code's effort levels per the owner's ruling ("更能直覺感受").
  `max` (weight 1.0) is a pure accuracy argmax — most accurate regardless of
  time — with equal-accuracy ties breaking to the faster candidate; that
  explicit tie-break also fixes a latent nondeterminism (the ranking sort was
  bare score-descending and Swift's sort is not stable). low/medium/high keep
  the old fast/balanced/accurate weight anchors, so measured behavior carries
  over under new names. **Migration**: `fast`→`low`, `balanced`→`medium`,
  `accurate`→`high` (or `max`); legacy names fail with exactly that hint (no
  alias layer, by ruling).
- **`auto` profile default reads dynamic machine state**: thermal pressure
  (serious/critical) or Low Power Mode downshifts the auto default to `low`,
  disclosed in `--explain` reasons; an explicit ordinal is never altered.
  New seam-injectable `DynamicHostState` probe degrades to no-pressure on
  failure — detection can never block a transcription.
- **README rewritten for 0.7.x reality**: effort-profile contract table,
  speaker diarization and voice-enrollment identification sections (both
  previously undocumented), explain walkthrough, updated command reference.
- **`diagnose` now resolves the profile the same way `transcribe`/`recommend`
  do** (#29 verify): it was pinned to `medium` and ignored the injected
  dynamic-state seam, so on a throttled machine it would report a different
  recommendation than the real runs. All three commands now share one
  source of truth for the default. Also: the shared profile parser no longer
  advertises `auto` in its error (which made `benchmark --profile auto`
  self-contradictory), and the benchmark capability spec gains the
  accurate→high delta the first-round dual-track sweep missed.


## [0.7.0] - 2026-07-03

### Added

- **Speaker identification by enrolled voice (#26)** — with `--diarize`, an enrollment
  sample under the resolved context directory's `voices/<name>.<ext>` folder labels that
  speaker's cues with the name verbatim (`[Alice] …`) instead of an ordinal; unmatched
  speakers keep `SPEAKER_N`, and enrolled names never consume an ordinal number. No new
  CLI surface — dropping a voice file into `voices/` is the whole interface; `--explain`
  reports `voices: N enrolled, M matched`. Identification is a self-owned post-hoc cosine
  match (`SpeakerIdentifier`, pure/unit-tested): the run's per-speaker embeddings are
  compared to each enrolled embedding under the SDK's 0.65 threshold — deliberately NOT
  the vendored SDK's known-speaker pre-load path, which on the DiarizerManager pipeline
  does not feed enrolled voices into clustering (verified: the pre-loaded speaker never
  entered the distance decision). `voices/` is reserved and local-only: never parsed as a
  context term, never in the ignored list, and — spec-level — never uploaded, committed,
  or transmitted off the machine (voice prints are sensitive biometric data).
  Reproducibly validated by `scripts/validate-diarization.sh`: a half-cut enrollment (the
  female recording's first 5.1s, definitionally the same person as the fixture's second
  half) labels that cue `TestVoice` while the male speaker stays `SPEAKER_1`. Identification
  is a self-owned post-hoc cosine match — the SDK's known-speaker pre-load path was
  probed and abandoned (it does not feed enrolled voices into DiarizerManager's
  clustering). Robustness: a corrupt or unreadable `voices/` sample is skipped with a
  warning rather than aborting the transcription; enrollment filenames are sanitized
  before reaching cue prefixes; the explain line reports `N/M enrolled` (embeddings
  obtained / files found); and `**/voices/` is git-ignored so voice prints never
  reach a remote. Enrollment embeddings use each speaker's LONGEST segment (not an
  arbitrary first fragment) for a more representative match; the explain line discloses
  when several diarized speakers collapse onto one name (`N name(s) matched across M
  diarized speaker(s)`) so a genuine two-people-one-name misattribution is visible; and
  the validation script asserts precision (an un-enrolled speaker is never labeled with
  an enrolled name) and cleans its biometric temp copy on any exit.

## [0.6.0] - 2026-07-03

### Added

- **Cue-level speaker diarization (#25)** — `bestasr transcribe --diarize` labels each
  cue with an acoustic speaker (`[SPEAKER_1] ` SRT/VTT prefixes, JSON `speaker` field,
  `SPEAKER_N: ` txt prefixes). Engine: FluidAudio pinned v0.15.4 (Apache-2.0, CoreML/ANE;
  models fetched and cached by the vendored SDK on first use). Assignment is a pure
  max-time-overlap function (`SpeakerAssigner`) — zero overlap yields no label rather
  than a fabricated one, ties go to the earlier turn, labels are first-appearance
  ordinals. Diarization failure with `--diarize` requested fails loudly — including
  the soft failure where the engine "succeeds" with no usable turns (a run whose
  assignment labels nothing refuses to emit output indistinguishable from the flag
  never being passed). Without the flag every output format is byte-identical to
  before (all four formats unit-pinned), and the acoustic layer is provably never
  invoked (injectable seam + spy test). Reproducibly validated by
  `scripts/validate-diarization.sh`: a pinned two-speaker fixture (same FLEURS
  sentence, male + female recordings, one second of silence at the join — cue-level
  assignment can only show a change where transcription breaks a segment, and the
  gap makes that break deterministic) switches SPEAKER_1→SPEAKER_2 exactly at the
  known 9.30s boundary; single-speaker jfk stays SPEAKER_1; the no-diarize run is
  clean. Speaker identification (real names) is #26.

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
