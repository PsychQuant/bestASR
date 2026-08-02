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

### Fixed

- **The regression gate reported exit 0 on real regressions (#134)**: three
  payloads made `scripts/lib/baseline-compare.py` print `✓ all corpora within
  tolerance` and **exit 0** while a 0.99 measurement sat against a 0.05 golden.
  This is fail-**open**, and it is categorically worse than a noisy log: a gate
  that says *pass* when it should say *fail* is not a weakened gate, it is an
  absent one still producing the reassuring output of a present one.

  - **Non-finite numbers.** Python's `json.load` accepts bare `NaN` /
    `Infinity`, and *every* comparison against NaN is false — so `diff > tol`
    was false and the entry "passed". Validation now happens **after**
    `float()`, which is the only place it works: rejecting the literal at parse
    time via `parse_constant` does not close the class, because `{"golden":
    "NaN"}` is a legal JSON *string* that never triggers it while
    `float("NaN")` still yields nan (likewise `1e999` → inf).
  - **An unbounded `tolerance`.** This path needs no unusual number at all,
    which is what made it hard to see: `tolerance: 1e308` rendered a 94-point
    regression as an ordinary pass line, indistinguishable from a real one.
    `tolerance` is now capped at **0.25**, the tightest per-field bound of the
    three, against a committed baseline that uses 0.02 throughout. Stated
    plainly, since the point of this change is that the prose must not flatter
    the gate: both that ceiling and the comparison are *inclusive*, so a
    regression of exactly 0.25 against a golden of 0 does pass. The bound
    refuses the absurd values; the tolerance now rendered on every passing line
    is what exposes the merely-too-lenient ones.
  - **A garbage numeric field** raised `ValueError` mid-run. A traceback is not
    a verdict; numeric fields now fail as a named gate error. (Scoped honestly:
    this covers the *numeric* converter. Malformed document shapes — a
    top-level array, a missing `corpus` or `language` key — still surface as
    tracebacks. They all exit non-zero, so none is fail-open, but the class is
    not uniformly handled and a shape guard after `json.load` is the follow-up.)

  `error_rate` is bounded differently on purpose: it is hazardous only when
  *non-finite*, because a large measurement correctly **fails**. Its ceiling is
  a garbage filter, not a security boundary.

  A cross-model verification round found four more ways the same verdict could
  come out wrong, each fixed here:

  - **A run that compared nothing reported success.** With the baseline and the
    measured set both empty, every loop was a no-op and the gate printed
    `all 0 corpora within tolerance` and exited 0 — so a fetch that produced no
    measurements read as *this release is safe*. A gate that verified no corpora
    has not passed; it has not run.
  - **A measurement judged against a different metric's golden.** `metric` was
    validated on the baseline side and never compared across, so a WER number
    could be scored against a CER threshold.
  - **A repeated JSON key hid the real threshold.** Python keeps the *last*
    value, so `{"golden": 0.9, "golden": 0.01}` silently became 0.01 — a decoy
    in the one file whose purpose is to be auditable by reading it. The existing
    duplicate-*corpus* check does not see this: that compares entries, this is
    one key repeated inside a single entry.
  - **A boolean laundered into a measurement.** `bool` subclasses `int`, so
    `float(true)` is 1.0 and a bare `true` passed every bound as an ordinary
    number.

  A second verification round found that bounding `tolerance` had closed one
  handle of a two-handled lever, and named the other:

  - **An inflated `golden` bought exactly the slack a wide `tolerance` was
    refused.** The decision is `actual - golden > tol`, so the gate passes
    anything at or below **`golden + tolerance`** — that sum is the effective
    threshold, and the two fields enter it identically. A `golden` of 2.0 with
    an honest `tolerance` of 0.02 admitted every physically possible error
    rate, and the tolerance newly rendered on the pass line read a reassuring
    `0.0200`, because the number that had moved was not the one being shown.
    Reproduced against the real committed baseline with a single field edited.
    The bound is now on **the sum** (`≤ 0.5`, against a committed maximum of
    0.1749) — the only bound invariant to trading one handle for the other.
    `golden`'s separate ceiling was **deleted**: with the sum bounded it could
    never be the guard that fired, and mutation testing put it at 0 of 34
    assertions. A constant no test can distinguish from its absence is not a
    guard.
  - **A truncated comparison still reported success.** Closing the empty case
    closed cardinality 0, not 1-of-N. Both sides of the comparison derive from
    the same `baseline.json` — the worklist stage reads it and the assembler
    iterates it — so deleting entries shrinks the baseline, the work list and
    the measured set together, and the gate prints `all 1 corpora within
    tolerance` over a release that verified one twelfth of what it should
    have. By pure deletion, with no unusual value anywhere. The expected corpus
    set is now pinned in `benchmarks/baseline-meta.json` and supplied to the
    compare stage by the gate, so truncating the baseline requires a second,
    deliberate edit to the file that carries the seeding provenance. A run with
    no anchor says so on stdout rather than passing quietly — a completeness
    check that can be skipped by omitting a key is the shape of the hole it
    closes.
  - **`OverflowError` escaped the numeric converter.** JSON has no integer
    width limit, so a bare 400-digit literal parses to an arbitrary-precision
    `int` and `float()` raises — neither `TypeError` nor `ValueError`. Exits
    non-zero, so never a bypass, but it reached the log as a stack trace where
    the verdict belongs. Universal, not version-specific. Rejected values are
    now also truncated at 120 characters, so a hostile field cannot become the
    log.

  A third round found that the completeness anchor could be switched off by
  omitting a key — the shape the fix was written against, one layer out — and
  that three guards had no test that could tell them from their absence:

  - **The anchor is now an invariant of the gate, not a nicety.**
    `scripts/regression-gate.sh` knows which baseline it is running, so for the
    repo's own it now **fails** when `baseline-meta.json` is missing,
    unreadable, or its `corpora` is absent / null / not a non-empty array of
    unique strings; an overridden `BESTASR_BASELINE` warns instead. The compare
    stage keeps tolerating an absent anchor with a printed NOTE, because a stdin
    filter genuinely cannot know whether it was handed a whole sweep — the
    invariant belongs where the answer is knowable. This also upgrades the #48
    model-artifact pin, which used to be skipped **silently** when that same
    file was missing.
  - **A satisfied anchor now says so** (`completeness: N corpora pinned by … —
    verified`). Its only previous evidence was the *absence* of the warning,
    which asks a reader to already know the warning exists — the same argument
    this entry makes for rendering the tolerance on passing lines.
  - **`error_rate: false`** was the one boolean position still able to flip a
    verdict, and nothing tested it: `float(false)` is `0.0`, a boolean laundered
    into a *perfect score* rather than a bad one. Every other position became
    redundantly covered once `golden` was bounded at 0.5 — which had quietly
    made the existing boolean test vacuous.
  - `expected_corpora` is shape-checked before use (a bare string would have
    been iterated character-wise; an int or a nested list raised a traceback),
    the anchor names the file it actually read rather than the default path, its
    corpus lists are length-capped, and the sum-bound message renders at 17
    significant digits so a rejected value cannot print as *equal* to the
    threshold it exceeded.

  Every guard is non-vacuous, measured by deleting each independently and
  counting failed assertions: effective-threshold bound **9**, completeness
  anchor **7**, boolean guard **6**, `isfinite` **5**, `TOLERANCE_MAX` **3**,
  `OverflowError` **3**, `ERROR_RATE_MAX` **2**, echo cap **2**, and the gate's
  own anchor wiring **1** — a one-token typo in that shell heredoc used to
  revert the whole completeness guard with a green suite.

  Those numbers come from **`scripts/mutation-check.sh`**, which is committed
  alongside them. A count a reader cannot re-run is the same defect as a
  threshold a reader cannot see, one level out; the script deletes each guard,
  re-runs the suite, restores the tree, and fails if anything scores zero.

  Passing lines now render **the tolerance they were judged against**. Auditing
  a pass is the whole purpose of this log, and the one number that could expose
  a rigged pass appeared only on *failing* lines — a reader checking a green run
  had no way to see that the bar had been lowered to meet it.

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
