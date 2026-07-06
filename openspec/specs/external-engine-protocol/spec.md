# external-engine-protocol Specification

## Purpose
Versioned JSON protocol for external ASR adapters — containment-first mounting for long-tail families (#51).

## Requirements

### Requirement: External adapters are invoked over a versioned JSON protocol

The system SHALL invoke a registered external engine by spawning its command as an argv array (never through a shell) with the subcommand `transcribe` and the flags `--audio <path>`, `--model <model>`, and optionally `--language <code>`, `--hf-repo <repo>`, `--revision <rev>`. On success the adapter SHALL write exactly one JSON object to stdout carrying `protocol` (integer version), `text` (string), `duration` (seconds), and optionally `segments` (array of `{start, end, text}`); the host SHALL reject a missing or unsupported `protocol` value. On failure the adapter exits non-zero and the host SHALL surface stderr in a typed `TranscriptionError` naming the backend — it SHALL NOT fall back to another backend.

#### Scenario: A conforming adapter transcribes through the seam

- **WHEN** a registered adapter exits 0 with `{"protocol":1,"text":"hello","duration":2.0}`
- **THEN** the transcription succeeds with that text as a single full-duration segment carrying the external backend id

#### Scenario: Adapter failure is loud and attributed

- **WHEN** the adapter exits non-zero with a message on stderr
- **THEN** a `TranscriptionError` names the external backend and carries the stderr message
- **AND** no other backend is silently tried

#### Scenario: An unsupported protocol version is rejected

- **WHEN** the adapter emits `"protocol": 99`
- **THEN** the host fails loudly naming the unsupported version instead of guessing at the payload shape

#### Scenario: Segments are optional

- **WHEN** the JSON carries a `segments` array with timed entries
- **THEN** the raw transcription uses those segments (clamped to the seam's timing defenses)

### Requirement: External processes are contained and time-bounded

Each transcription SHALL run in its own process (no resident worker): runtime environments (e.g. a Python venv) belong to the adapter's wrapper script, and the host carries no knowledge of them. The host SHALL enforce a timeout of at least `max(120s, 4x audio duration)`, terminating the process on expiry and failing loudly. A crashed or hung adapter SHALL never corrupt host state.

#### Scenario: A hung adapter is terminated

- **WHEN** the adapter produces no exit within the timeout
- **THEN** the process is terminated and a `TranscriptionError` reports the timeout

### Requirement: External engines register through a user config

The system SHALL read `~/.bestasr/engines.json` (`{"engines":[{"id": "<backend-id>", "command": ["<argv>", ...]}]}`). An entry whose id matches a known external-capable backend enables that backend; an unknown id SHALL warn and be ignored (the config is hand-written); a registered command whose executable does not exist SHALL leave the backend unavailable. With no config present, behavior is identical to a build without this capability.

#### Scenario: No config means no external backends

- **WHEN** `~/.bestasr/engines.json` does not exist
- **THEN** no external backend reports availability and enumeration matches the pre-#51 behavior

#### Scenario: A registered adapter enables its backend

- **WHEN** the config registers `mlx-audio` with an existing executable
- **THEN** the `mlx-audio` backend reports available and its catalog rows enumerate as candidates

### Requirement: External measurements are comparable and honestly labeled

External engines SHALL flow through the same benchmark pipeline (same text normalization, same WER/CER metrics) as bundled engines. Their realtime factor SHALL include the full process lifetime (spawn, model load, transcription) — the per-call cost is a structural property of the one-process-per-call containment model and SHALL NOT be masked by excluding warm-up.

#### Scenario: External RTF is end-to-end

- **WHEN** an external engine is benchmarked
- **THEN** its recorded realtime factor covers the whole process lifetime, and quality metrics are computed by the same normalizer as bundled engines


<!-- @trace
source: external-process-engine
updated: 2026-07-06
code:
  - Sources/BestASRKit/Engines/ExternalProcessEngine.swift
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Router/Router.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Sources/BestASRKit/CommandCore.swift
  - adapters/mlx-audio/bestasr-mlx-adapter.py
  - adapters/mlx-audio/setup.sh
  - Tests/BestASRKitTests/ExternalEngineTests.swift
  - README.md
  - CHANGELOG.md
-->
