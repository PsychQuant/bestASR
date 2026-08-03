# Changelog

All notable changes to bestASR are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

### Added

- **Apple Speech backend (#121)**: `apple-speech` — the OS-native backend
  (Speech.framework's `SpeechAnalyzer` / `SpeechTranscriber`, macOS 26+). The
  only backend in the pool with no third-party dependency and no HuggingFace
  weight pin: the recognizer ships with the operating system, so **its version
  IS the OS version**. That is a claim about *provenance*, not about network
  traffic — a locale whose asset is absent is still downloaded from Apple on
  first use, as `ja_JP` was here. Registered unconditionally; `isAvailable()` is a pure
  macOS-26 gate, so older hosts report it as not installed rather than failing
  to build. One grid row (`apple-speech · speechanalyzer/system`), priority 1,
  **`verified: false`** — the API is live-probed but the row is not yet measured
  on this project's corpora, and `estMemoryGB` 2.0 is an explicit **unmeasured
  placeholder**.

  Three behaviors were established by live probing, not from the headers, and
  are load-bearing enough to record here:

  - The `results` `AsyncSequence` must be consumed **before** audio is fed, or
    results are lost.
  - A missing locale asset surfaces as `SFSpeechErrorDomain Code=3 "Audio
    format is not supported"` — a **misleading message**. Proved not to be a
    format problem (three corpora byte-identical in format behaved differently;
    the same ja file transcribed fine under `en_US`; installing the ja asset
    fixed it immediately). The engine therefore checks `installedLocales` and
    downloads on demand, and never diagnoses from the error text.
  - The framework exposes **no determinism knob** (`Speech.swiftinterface` has
    zero hits for temperature/greedy/beam/sampling/seed), so this backend
    records `flag-not-consumed` for `decode_deterministic` (#118) rather than
    claiming an enforcement it cannot perform.

  Language is **required**: `SpeechTranscriber` selects its model by locale and
  has no auto-detect mode, so an unresolved language throws instead of guessing
  — a ja file decoded under `en_US` yields measured garbage, and a benchmark
  harness must not admit a silent guess into its evidence base. `zh` maps to
  `zh_TW` to match the project's Common Voice zh-TW corpora. Per-segment
  confidence is **derived** (the minimum over Apple's per-run values), so a
  confident run cannot mask a weak one inside the same cue.

  **First measured numbers** (M5 Max, macOS 27, single corpus per language —
  indicative, not a certification; the row stays `verified: false` until a full
  sweep):

  | corpus | metric | apple-speech | whisperkit large-v3-turbo |
  |---|---|---|---|
  | `cv-zhtw-2` (zh) | CER | **13.9 %** @ 63–65× realtime | 12.5 % @ 7.1× |
  | `fleurs-ja-1` (ja) | CER | **10.9 %** @ 85× realtime | 10.6 % @ 6.9× |
  | `librispeech-testclean-1` (en) | WER | **4.3 %** @ 58× realtime | not yet measured |
  | `librispeech-devclean-1` (en) | WER | **4.1 %** @ 45× realtime | not yet measured |

  So on this machine Apple lands within ~1.4 pp of Whisper large-v3-turbo on
  zh and ~0.3 pp on ja, at roughly **9–12× the speed** and with no model to
  download or hold resident. Reported `peak-GB` is 0.00 because recognition
  runs in Apple's out-of-process daemon — the harness's in-process sampler
  cannot see that footprint, so this backend's memory column is **not
  comparable** with the in-process backends'.

- **Release sweep (#109)**: `scripts/release-sweep.sh` — the per-version
  deterministic measurement snapshot. Runs the priority-1 runnable candidates
  (default ceiling; `--all-grid` widens to the whole grid) over the **canonical
  community corpora** (`bestasr bench pull`) with `--decode-deterministic`
  (binding for Whisper-family backends; a silent no-op elsewhere — see the
  `decode_deterministic` entry below), so the local
  store gains a "performance of each model under this pinned version" record
  (measurements carry `app_version` / `macos_version` / machine id). Canonical
  corpora are what `bestasr bench submit` can publish — the bench leaderboard
  renders per-version snapshots by grouping on `app_version` + chip. A version
  guard refuses to sweep with a binary older than the checkout, and the
  epilogue prints a per-corpus candidate census so partial matrices are
  visible. Supports `--dry-run` and `--backends`/`--models` subset filters.
  Not a gate — the regression gate in `release.sh` remains the release
  blocker; the sweep is the evidence regime run after each release.

- **Measurement provenance fields (#111)**: `MeasurementRow` / `SubmissionRow`
  gain two **optional** fields, mirroring the `hf_revision` precedent (absent
  keys decode to nil, so existing rows and submissions stay valid).
  `run_kind` (`release-sweep` | `adhoc`) marks how a row was produced, so a
  per-version snapshot's candidate census can be checked mechanically instead
  of assumed; the new `bestasr benchmark --run-kind` flag carries it, and
  `scripts/release-sweep.sh` stamps `release-sweep`. `decode_deterministic`
  records the decode condition as a **three-value enum** (#118):
  `deterministic-enforced` / `fallback-enabled` for backends that actually
  consume `--decode-deterministic` (WhisperKit, whisper.cpp), and
  `flag-not-consumed` for backends that ignore it (mlx-audio's is a silent
  no-op; the Fluid backends have no such knob) — which makes no claim about
  whether those decodes are reproducible, rather than lying in either
  direction. An **absent** field still means "legacy row, predates the field";
  `null` is never written, though a reader accepts it as equivalent to absent.
  A value the reader does not recognize — including a `decode_deterministic`
  boolean from the earlier shape of this same unreleased entry — is **rejected**,
  not coerced; no released version ever wrote one, and no row in either repo or
  any local store carries one. The bench side validates both only when present
  (`PsychQuant/bestASR-bench@c93a70e`).

  `--run-kind` also gained a value domain at the CLI (#120): a typo now fails at
  parse (`exit 64`) instead of surviving into a submission and failing in the
  bench repo's CI. The stored field stays a plain string on purpose — that
  vocabulary is human-typed provenance and already incomplete (the regression
  gate benchmarks with no `--run-kind` at all), so closing it at the row type
  would trade a loud CI failure for a silently dropped row.

### Changed

- **FluidAudio pinned 0.15.4 → 0.15.5 (#122)**: 0.15.5 completes the Parakeet
  Unified frontend — the CoreML preprocessor bundle is dropped in favour of a
  native Swift mel extractor, and the streaming encoder gains a per-latency-tier
  context suffix — which is what #123 needs. **TDT-ja was already reachable at
  0.15.4**: `AsrModelVersion.tdtJa` and the `parakeet-0.6b-ja-coreml` repo are
  present and byte-identical there, and the `Unified*` managers exist there too
  — they are not byte-identical, which is the point: 0.15.5 rewrites their
  frontend rather than introducing them. An earlier
  version of this entry said the models "exist only in 0.15.5"; that was wrong,
  and it put #124's *blocked by #122* premise in doubt along with it.

  #110 flagged `DownloadUtils → ModelHub` as a breaking change. It is not one
  *for this repo* — **no compiled call site references either symbol** (verified
  repo-wide, not inferred from the build) — but two narrower claims in the first
  version of this entry were false:

  - **The `AsrModels` signatures did change.** Every public entry point took
    `progressHandler: DownloadUtils.ProgressHandler?` and now takes
    `progressHandler: ProgressHandler?`, as did every other consumed factory.
    Source-compatible here only because this repo never passes one — which is a
    different statement from "unchanged", and the issue's open question asked
    for the first, not the second.
  - **The consumed surface is not "entirely high-level."** The enumeration
    omitted `DiarizerModels.downloadIfNeeded()`, `AudioConverter.resampleAudioFile`,
    `DiarizerManager.initialize` / `.performCompleteDiarization`, and
    `AsrModelVersion`. The first of those is a **download-layer entry point**,
    which undercuts the framing that the download-layer rewrite cannot reach
    this repo: it reaches it through a facade rather than by name.

  Two behaviour changes on call sites this repo does use went unmentioned and
  are benign: `AsrModels.download` now performs an extra fetch of the vocab JSON
  (upstream #748 — the weight manifest already pins both vocab files, so the
  newly-guaranteed fetch lands *inside* the pinned set), and
  `performCompleteDiarization` gained a defaulted trailing `progressHandler`.

  **Accuracy: an identical transcript on a corpus that could have differed.**

  `ChunkProcessor` was touched by **two** upstream commits carrying **five**
  distinct changes, not the one the first version of this entry named.

  `7e856da4` (#706/#708) contributes two: `caseVariantCanonicalIds` feeds a new
  post-merge `collapseSeamWordDuplicates` — case-gated, Latin-gated — *and* is
  threaded into the overlap matcher itself, where `tokensMatch` went from exact
  token-ID equality to case-folded equality. The second is easy to miss and is
  the more interesting one: it changes which token pairs anchor the merge, i.e.
  **where the seam is cut**, rather than what is removed afterwards.

  `0ac0e414` (#683/#759) contributes three word-boundary-safe fallbacks on
  seam-merge drop paths, keyed off `spliceSafeTokenIds`. Neither case- nor
  Latin-gated — but all three are **strictly conditional**, differing from 0.15.4
  only when no splice-safe token exists at the seam. Upstream's own
  instrumentation in that commit message reports ~67 chunk-merge events over
  ~15 minutes of deliberately adversarial agglutinative audio hitting the guarded
  logic on ~70 % of seams and **never falling through to any of the three**. They
  are defensive.

  The first version of this entry named only the first commit, and wrote off all
  seven of its rows on that basis. The honest decomposition is narrower:

  | row | path | blind to the merge change? |
  |---|---|---|
  | `jfk` parakeet | 11.0 s → **one chunk** | yes — the merger never runs |
  | `cv-zhtw-4` parakeet | 25.68 s → **two chunks** | **no** — it exercises `0ac0e414`'s fallbacks |
  | 3 × sensevoice, 2 × paraformer | never enter `ChunkProcessor` at all | yes, but because of the subtree, not because of case |

  So the old table could not support "accuracy is unchanged" — one of its two
  parakeet rows was structurally blind and the other confounds six bestASR
  versions — but it was not empty, and the reason five of its rows carried no
  information was the ASR subtree they run in, not the absence of case.

  Measured on a corpus that **can** exercise it — `osr-harvard-1`, 33.6 s of
  English — by building the same tree against each pin in turn:

  | pin | corpus | backend | WER |
  |---|---|---|---|
  | 0.15.4 (`b9d43724`) | `osr-harvard-1` | parakeet | **0.037500** |
  | 0.15.5 (`19600a48`) | `osr-harvard-1` | parakeet | **0.037500** |

  Bit-identical, not equal-after-rounding. The resolved version string alone
  would not settle which code actually ran — a stale build artifact can survive
  a pin change — and neither does the checked-out source, for the same reason.
  The artifact to interrogate is the **binary**: `nm` on the built `bestasr`
  reports the `ChunkProcessor.caseVariantCanonicalIds` symbol present under the
  0.15.5 pin and absent under 0.15.4.

  What this does and does not establish, stated narrowly because two earlier
  attempts at this paragraph overstated it in opposite directions.

  The transcripts are byte-identical. Worked backwards, that is itself evidence
  that **none of the five changes was reached**: the collapse is case-gated and a
  clean reading passage has no case-differing seam duplicate; the three fallbacks
  differ only where no splice-safe token exists, and any non-degenerate entry
  would have kept content 0.15.4 dropped; the matcher's case-folding can only
  move a seam where a case-variant pair exists to anchor on.

  So this run does **not** show that the changed code produces the same output.
  It shows that a 33.6 s English multi-chunk corpus — one whose shape makes every
  one of the five reachable in principle, unlike `jfk` or a caseless one — comes
  out identical, with no evidence that any of them was entered. That is a weaker
  claim than "accuracy is unchanged" and a stronger one than the removed table
  could make: it is a measurement that could have come out differently.

  Exercising the collapse deliberately would need audio with a case-variant
  repetition across a ~15 s boundary; the fallbacks, per upstream, resisted 67
  adversarial seams. Neither is in this repo's corpus set, and constructing them
  is #123/#124 work rather than a dependency bump's.

  **The earlier table was not a before/after comparison at all**, and is removed
  rather than repaired. Its "0.15.4" column reconciles to store rows captured
  `2026-07-05/06` under **app_version 0.10.0**; its "0.15.5" column is the
  `2026-08-02` batch under **0.16.0** — four weeks and six bestASR versions
  apart. A `fluid-*` batch does exist in between (24 rows on `2026-07-19` under
  `0.14.0`), and it shares **zero corpora** with the after-batch, which is what
  forced the older rows into the "before" column: the choice was constrained by
  overlap, not made carelessly. The seven pairs are in fact bit-identical in the
  store (the mismatched 2 dp / 1 dp rendering obscured that), which is real
  evidence that those paths are deterministic and unmoved across six app
  versions; it is simply not evidence about this dependency bump.
  Issue #122 asked for a sweep on **each side** of the upgrade, and only the
  after side was ever run.

  Two labelling corrections while the table is being rewritten: the figures are
  **error rates**, not "accuracy" — values like 178 % are impossible under any
  bounded accuracy definition, and the earlier heading inverted the direction as
  well as the meaning. And two of the seven rows were `fluid-paraformer`, which
  the grid marks `priority: 2, verified: false` and the sweep script excludes by
  default as "demoted for a known upstream decode bug"; stable numbers from a
  known-broken backend evidence that the bug is stable, not that quality is
  preserved.

  Throughput moved (parakeet on `jfk` 161.6× → 126.5×, a 21.7 % single-run
  decline). One uncontrolled run is not enough to attribute that to the
  dependency — but calling it "not evidence of a change either way" was too
  strong. It is weak evidence, and the honest form is that this run cannot
  attribute the difference, not that no difference was observed.

  **Comparability caveat, carried from #110's residue**: the measurement schema
  records `app_version` (bestASR's own) but **not** the FluidAudio version, so a
  row cannot be attributed to a dependency version from the store alone. (An
  earlier version of this caveat said the two batches were "indistinguishable in
  the store"; they are not — they differ in `app_version` and in
  `decode_deterministic`. The sentence described a hypothetical confound while
  the real one, six app versions, went unstated.) Per the standing rule that a
  tool version change makes a new *condition*, rows either side of this bump
  should not be ranked against each other on the strength of the schema alone;
  the durable fix is a `build_id` or lockfile hash on the row, which is #111 /
  #118 territory rather than this change's.

  **Not covered here**: the diarizer subtree also moved substantially upstream
  (`KMeansClustering`, `OfflineReconstruction`, new `ZeroVoteReembedder` /
  `OfflineEmbeddingExtractor` / `OfflineSortformerDiarizer`), and this repo
  consumes diarization. No DER row exists on either side of the bump and
  `scripts/validate-diarization.sh` was not run, so that surface is
  **unestablished rather than unchanged**. Separately, `weights-manifest.json`
  still pins `silero-vad-unified-256ms-v6.0.0` while 0.15.5 moved to `v6.2.1` —
  inert today (this repo has no VAD usage and no seam verifies that repo), and
  recorded because it demonstrates the pinning mechanism's blind spot: an
  upstream **rename** degrades a repo from "pinned" to "effectively unverified"
  without ever failing loudly, since `WeightVerifier` iterates manifest entries
  only and extra cache files never fail.

### Fixed

- **`--backend apple-speech` was silently substituted (#121)**: `Router`'s
  backend-membership list omitted the new backend, so an explicit `--backend
  apple-speech` was discarded and another backend's output was written under
  the user's chosen name. The accompanying `unavailable` warning was both
  **false** (`isAvailable()` returns true on macOS 26+) and invisible without
  `--explain`. Measured before the fix: the command produced mlx-audio Whisper
  output in **Simplified** Chinese; after it, genuine Apple Speech output in
  **Traditional**. `ModelRegistry.isRunnableModel` gained the same membership so
  `--model system` resolves.

- **`zh-Hans` selected the Traditional model (#121 verify)**: language subtags
  were read **by position**, so the script subtag in `zh-Hans` was taken for a
  region, matched no locale, and fell through to the `zh` preference — a user
  who explicitly asked for **Simplified** silently received **Traditional**.
  Subtags are now classified by **shape** (BCP-47: script is 4 alpha, region is
  2 alpha or 3 digits), with `Hans → CN` / `Hant → TW`; an explicit region still
  outranks a contradicting script (`zh-Hans-TW` → `zh_TW`).

- **Provenance recorded the requested language, not the one that ran (#121
  verify)**: asking for `pt-BR` on a system shipping only `pt_PT` produced a
  measurement labelled `pt-BR`. The resolved locale is now recorded, in
  hyphenated form — Apple's underscored `zh_TW` would otherwise defeat
  `LanguageResolver.baseSubtag` (which splits on `-` only) and silently disable
  the D7 Traditional/Simplified fold for this backend's zh scoring.

- **Locale asset downloaded before the audio file was validated (#121
  verify)**: `transcribe --language ja /nonexistent.wav` could fetch a
  multi-hundred-MB asset and only then report the missing file. The file is now
  opened first. Additionally, a nil installation request no longer falls through
  to Apple's misleading `"Audio format is not supported"`: `installedLocales` is
  re-checked after the attempt and a still-absent asset fails with that
  explanation.

- **Recognized speech could vanish silently (#121 verify)**: a result with
  unusable timing was dropped. Because the WER denominator is the reference word
  count and does not move, a dropped correct word adds a deletion while a dropped
  garbage word removes an insertion — the measured rate shifts in an unsignposted
  direction. Non-empty text with unusable timing now **fails the run**. Only
  truly-empty text is dropped; whitespace-only segments are kept, since
  `Engine.transcribe` joins with no separator and discarding the separator would
  glue neighbouring words.

- **Orphaned collector task (#121 verify)**: the unstructured `Task` reading
  `transcriber.results` was neither awaited nor cancelled when the analyzer
  threw, pinning the transcriber and its buffers for the life of the process —
  which accumulates across a benchmark sweep. It is now cancelled on every exit.

- **The compare stage no longer renders baseline values unescaped (#117)**:
  `scripts/lib/baseline-compare.py` interpolated `corpus` / `language` /
  `metric` straight into the pass/fail lines it prints, and that stdout is the
  log a human reads to decide whether a release is safe. `metric` was validated
  **nowhere**: the worklist stage checks corpus and language, and `metric` is
  the only rendered field that is neither charset-checked nor numeric, so it
  reaches the log as-is. (`float()` on the numbers is a *conversion*, not a
  validation — it accepts `NaN` and `Infinity`; see #134.) A committed baseline
  carrying `"cer\x1b[32m\rFAKE ALL-PASS"` repainted the
  line into a forged green verdict, with no timing window needed. `metric` now
  has to be `cer` or `wer`, and every rendered value is wrapped in an escaper
  that neutralizes C0/DEL/C1 — enough that no value can emit an ANSI sequence or
  return the cursor. Escaped rather than stripped, so the value stays visible.
  Two honest limits: the wrapping is explicit at each interpolation, so a new
  f-string is not covered until someone wraps it; and Unicode format characters
  (U+2028, bidi overrides) are out of scope — they need no control byte, and are
  unreachable here only because corpus and language are whitelisted upstream.

- **Baseline field validation extracted to a tested lib, and `model` validated
  (#116, #115)**: the gate parsed `baseline.json` in two independent inline
  heredocs — the worklist stage (`corpus` + `language`) and the model stage
  (`entries[0].model`, validated nowhere). Neither was reachable by a test
  without running the whole gate, while the compare stage has been a tested lib
  since #34. `scripts/lib/baseline-worklist.py` now owns the validation
  (`--emit worklist|model`), and **both modes run the complete field pass** —
  validating only the emitted field would recreate the divergence that let
  `model` go unchecked. `model` gains a whitelist: a single path component
  starting alphanumeric, no `/`, `..` rejected outright. It reaches a `cd`
  target and a CLI arg, so #112 had not removed the traversal capability — only
  moved the payload one field over. The extracted worklist output is
  byte-identical to the heredoc's (pinned by sha in the test).

- **Baseline `language` field validated before the worklist TSV (#112)**:
  `scripts/regression-gate.sh` whitelisted the `corpus` field but wrote
  `language` into the same line-oriented TSV unchecked, so an embedded newline
  could forge a worklist record whose corpus field never passed the charset
  check (reproduced against `corpora/../`). `language` now takes the same
  `re.fullmatch` discipline and fails loud. Defense in depth — `baseline.json`
  is version-controlled and the gate publishes nothing, so exploiting it
  required landing a hostile baseline first.

### Changed

- **BREAKING — context directory renamed (#107)**: the working-directory context
  layer moved from `./bestasr-context/` to `./.bestasr/context/`, matching the home
  layer `~/.bestasr/context/`. The legacy `./bestasr-context/` is no longer
  resolved. **Migration**: rename the existing directory, e.g. run
  `mv bestasr-context .bestasr/context` in the project root.

## [0.14.0] - 2026-07-17

### Added

- **Confidence-gated hallucination filtering (#100)**: `--hallucination-filter
  full` drops cues by Whisper's per-segment signals — the joint silence rule
  (`no_speech_prob > 0.6` AND `avg_logprob < -1.0`) and the repetition rule
  (`compression_ratio > 2.4`) — on top of the denylist. Backends that don't
  compute the signals (whisper.cpp, Parakeet) degrade to `denylist`
  automatically; output formats unchanged.
- **WhisperKit decode-param knobs (#101)**: `--no-speech-threshold`,
  `--compression-ratio-threshold`, `--logprob-threshold` (WhisperKit only;
  unset rides WhisperKit's own defaults) suppress hallucinations at decode
  time, complementing the post-decode filter. Negative values parse in space
  form (`--logprob-threshold -1.0`).

## [0.13.0] - 2026-07-16

### Added

- **Hallucination filter (#98)**: a backend-agnostic post-decode pass that strips
  known ASR hallucinations — silent-segment boilerplate (the Whisper-family
  "please like & subscribe" outros that surface verbatim over silence), empty
  cues, and adjacent exact-duplicate cues — before the transcript is written.
  New `--hallucination-filter <off|denylist>` on the CLI and `hallucination_filter`
  on the MCP `transcribe` tool. Applied at the single `CommandCore.transcribe`
  choke point, after diarization, so speaker labels on surviving cues are kept.
  The denylist content is Whisper-family, so it is a no-op for backends that
  never emit those strings.

### Changed

- **Transcripts are cleaned by default (#98)**: transcription now runs the
  hallucination filter in `denylist` mode by default, so known boilerplate no
  longer reaches the output (`srt`/`txt`/`json`/`vtt`) and downstream
  `srt-proofread` no longer has to strip it. Pass `--hallucination-filter off`
  (CLI) or `hallucination_filter: "off"` (MCP) to restore the raw output.

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
