# asr-engine Specification

## Purpose

TBD - created by archiving change 'bestasr-mvp'. Update Purpose after archive.

## Requirements

### Requirement: Common engine interface

Every ASR backend SHALL implement the common `Engine` interface (`id`, `isAvailable`, `transcribeRaw`), and `BackendID` SHALL enumerate exactly the backends with a bundled runtime: `whisperkit`, `whisper.cpp`, and `fluid-parakeet`.

#### Scenario: Three backends enumerate

- **WHEN** `BackendID.allCases` is consulted (e.g. by `list-backends`)
- **THEN** it yields `whisperkit`, `whisper.cpp`, and `fluid-parakeet`, each constructible as an engine

#### Scenario: Non-Whisper engine inherits the normalization seam

- **WHEN** any input that is not 16 kHz mono is transcribed through `Engine.transcribe` with the fluid-parakeet backend
- **THEN** the engine's `transcribeRaw` receives the normalized 16 kHz mono path (AudioNormalizer, #36), identical to the Whisper backends


<!-- @trace
source: add-parakeet-cross-family-engine
updated: 2026-07-06
code:
  - Sources/BestASRKit/Engines/ParakeetEngine.swift
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Models/ModelGrid.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Router/Router.swift
  - Sources/BestASRKit/CommandCore.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ParakeetEngineTests.swift
  - Tests/BestASRKitTests/RouterTests.swift
  - README.md
  - CHANGELOG.md
-->

---
### Requirement: Availability detection is graceful

`is_available()` SHALL determine whether the underlying package and runtime are usable by probing via lazy import or an equivalent runtime probe, and SHALL return false rather than raising when the package or runtime is absent.

#### Scenario: Uninstalled backend reports unavailable

- **WHEN** `is_available()` is called for a backend whose underlying package is not installed
- **THEN** it returns false
- **AND** no ImportError propagates to the caller


<!-- @trace
source: remove-mlx-audio-backend
updated: 2026-07-04
code:
  - Tests/BestASRKitTests/DiarizationTests.swift
  - Sources/BestASRKit/Engines/mlx_worker.py
  - Sources/BestASRKit/Diarize/SpeakerIdentifier.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - Tests/BestASRKitTests/RouterTests.swift
  - Package.swift
  - docs/design-brief.md
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Engines/MLXAudioEngine.swift
  - CHANGELOG.md
  - README.md
  - Sources/BestASRKit/CommandCore.swift
  - Sources/BestASRKit/Diarize/SpeakerAssigner.swift
  - Tests/BestASRKitTests/DataModelTests.swift
  - Package.resolved
  - Sources/BestASRKit/Diarize/SpeakerEnroller.swift
  - Tests/BestASRKitTests/ModelGridTests.swift
  - Tests/BestASRKitTests/PipelineWiringTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Engines/MLXWorkerProtocol.swift
  - scripts/validate-diarization.sh
  - Sources/BestASRKit/Store/StoreTables.swift
  - Sources/BestASRKit/Detect/DynamicHostState.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Models/ModelGrid.swift
  - Sources/BestASRKit/Router/Ranking.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Sources/BestASRKit/Store/BenchmarkStore.swift
  - scripts/fetch-corpora.sh
  - Tests/BestASRKitTests/MLXAudioEngineTests.swift
  - Tests/BestASRKitTests/EffortProfileTests.swift
  - CLAUDE.md
  - Tests/BestASRKitTests/CLITests.swift
  - Sources/BestASRKit/Diarize/DiarizationEngine.swift
  - Sources/bestasr/BestASRCommand.swift
  - Sources/BestASRKit/Router/Router.swift
  - .claude-plugin/marketplace.json
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Output/TranscriptWriter.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Tests/BestASRKitTests/BenchmarkStoreTests.swift
-->

---
### Requirement: Transcription returns a normalized Transcript

`transcribe` SHALL return a `Transcript` carrying `text`, `language`, `duration`, an ordered list of `TranscriptSegment`, and the `backend` and `model` used. Each `TranscriptSegment` SHALL carry `id`, `start`, `end`, `text`, and an optional `confidence`.

#### Scenario: Transcript carries segments and metadata

- **WHEN** a backend transcribes an audio file successfully
- **THEN** the returned `Transcript` has non-null `text`, a `segments` list ordered by `start`, and `backend` and `model` set to the values used


<!-- @trace
source: bestasr-mvp
updated: 2026-07-01
code:
  - bestasr/engines/mlx_whisper_engine.py
  - bestasr/output/srt.py
  - bestasr/__init__.py
  - bestasr/detect/language.py
  - bestasr/detect/system.py
  - bestasr/output/json_writer.py
  - bestasr/router/profiles.py
  - bestasr/utils/ffmpeg.py
  - bestasr/output/txt.py
  - bestasr/engines/faster_whisper_engine.py
  - bestasr/models/requirements.py
  - examples/diagnose.sh
  - pyproject.toml
  - README.md
  - bestasr/detect/__init__.py
  - bestasr/output/_timecode.py
  - tests/conftest.py
  - bestasr/cli.py
  - bestasr/engines/__init__.py
  - bestasr/models/__init__.py
  - bestasr/output/__init__.py
  - bestasr/router/recommendation.py
  - bestasr/engines/base.py
  - bestasr/detect/acceleration.py
  - bestasr/models/registry.py
  - bestasr/router/rules.py
  - bestasr/engines/whisper_cpp_engine.py
  - bestasr/output/vtt.py
  - examples/recommend.sh
  - bestasr/router/__init__.py
  - bestasr/router/scorer.py
  - bestasr/detect/audio.py
  - bestasr/utils/__init__.py
  - examples/basic_transcribe.sh
  - bestasr/detect/hardware.py
tests:
  - tests/test_output_formats.py
  - tests/test_router.py
  - tests/test_audio_detection.py
  - tests/test_fixtures.py
  - tests/test_readme_examples.py
  - tests/test_dataclasses.py
  - tests/test_engines.py
  - tests/test_hardware_detection.py
  - tests/test_cli.py
-->

---
### Requirement: Estimate model requirements

`estimate_requirements(model_name)` SHALL return the estimated memory footprint used by the router to decide feasibility and downgrades, sourced from a static requirements table.

#### Scenario: Requirement estimate available for each model size

- **WHEN** `estimate_requirements` is called for a supported model name
- **THEN** it returns a `ModelRequirements` value with a positive estimated memory figure


<!-- @trace
source: bestasr-mvp
updated: 2026-07-01
code:
  - bestasr/engines/mlx_whisper_engine.py
  - bestasr/output/srt.py
  - bestasr/__init__.py
  - bestasr/detect/language.py
  - bestasr/detect/system.py
  - bestasr/output/json_writer.py
  - bestasr/router/profiles.py
  - bestasr/utils/ffmpeg.py
  - bestasr/output/txt.py
  - bestasr/engines/faster_whisper_engine.py
  - bestasr/models/requirements.py
  - examples/diagnose.sh
  - pyproject.toml
  - README.md
  - bestasr/detect/__init__.py
  - bestasr/output/_timecode.py
  - tests/conftest.py
  - bestasr/cli.py
  - bestasr/engines/__init__.py
  - bestasr/models/__init__.py
  - bestasr/output/__init__.py
  - bestasr/router/recommendation.py
  - bestasr/engines/base.py
  - bestasr/detect/acceleration.py
  - bestasr/models/registry.py
  - bestasr/router/rules.py
  - bestasr/engines/whisper_cpp_engine.py
  - bestasr/output/vtt.py
  - examples/recommend.sh
  - bestasr/router/__init__.py
  - bestasr/router/scorer.py
  - bestasr/detect/audio.py
  - bestasr/utils/__init__.py
  - examples/basic_transcribe.sh
  - bestasr/detect/hardware.py
tests:
  - tests/test_output_formats.py
  - tests/test_router.py
  - tests/test_audio_detection.py
  - tests/test_fixtures.py
  - tests/test_readme_examples.py
  - tests/test_dataclasses.py
  - tests/test_engines.py
  - tests/test_hardware_detection.py
  - tests/test_cli.py
-->

---
### Requirement: Transcription failure is surfaced

When a backend fails to transcribe (for example a decode error or a missing runtime dependency such as ffmpeg), it SHALL raise a clear, typed error rather than returning an empty or partial `Transcript` silently.

#### Scenario: Decode failure raises

- **WHEN** `transcribe` is given an unreadable or unsupported audio input
- **THEN** a clear error is raised describing the failure

<!-- @trace
source: bestasr-mvp
updated: 2026-07-01
code:
  - bestasr/engines/mlx_whisper_engine.py
  - bestasr/output/srt.py
  - bestasr/__init__.py
  - bestasr/detect/language.py
  - bestasr/detect/system.py
  - bestasr/output/json_writer.py
  - bestasr/router/profiles.py
  - bestasr/utils/ffmpeg.py
  - bestasr/output/txt.py
  - bestasr/engines/faster_whisper_engine.py
  - bestasr/models/requirements.py
  - examples/diagnose.sh
  - pyproject.toml
  - README.md
  - bestasr/detect/__init__.py
  - bestasr/output/_timecode.py
  - tests/conftest.py
  - bestasr/cli.py
  - bestasr/engines/__init__.py
  - bestasr/models/__init__.py
  - bestasr/output/__init__.py
  - bestasr/router/recommendation.py
  - bestasr/engines/base.py
  - bestasr/detect/acceleration.py
  - bestasr/models/registry.py
  - bestasr/router/rules.py
  - bestasr/engines/whisper_cpp_engine.py
  - bestasr/output/vtt.py
  - examples/recommend.sh
  - bestasr/router/__init__.py
  - bestasr/router/scorer.py
  - bestasr/detect/audio.py
  - bestasr/utils/__init__.py
  - examples/basic_transcribe.sh
  - bestasr/detect/hardware.py
tests:
  - tests/test_output_formats.py
  - tests/test_router.py
  - tests/test_audio_detection.py
  - tests/test_fixtures.py
  - tests/test_readme_examples.py
  - tests/test_dataclasses.py
  - tests/test_engines.py
  - tests/test_hardware_detection.py
  - tests/test_cli.py
-->