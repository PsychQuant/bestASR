# asr-engine Specification

## Purpose

TBD - created by archiving change 'bestasr-mvp'. Update Purpose after archive.

## Requirements

### Requirement: Common engine interface

Every backend SHALL implement the common engine interface with `is_available() -> bool`, `transcribe(audio_path, options) -> Transcript`, and `estimate_requirements(model_name) -> ModelRequirements`. Transcribe options SHALL carry the model, the quantization variant, the optional language, and an optional context prompt. When a context prompt is present, the engine SHALL forward it to its backend's prompt mechanism (the WhisperKit decode-options prompt path; the whisper-cli prompt flag); when absent, no prompt SHALL be passed. The supported backend implementations SHALL be `whisperkit` (CoreML/ANE path) and `whisper.cpp` (GGUF quantized path).

#### Scenario: Each backend exposes the interface

- **WHEN** any supported backend is instantiated
- **THEN** it provides `is_available`, `transcribe`, and `estimate_requirements` with the specified signatures

#### Scenario: Quantization is part of transcribe options

- **WHEN** an engine is asked to transcribe with a quantization variant its backend supports
- **THEN** the engine loads the model matching that quantization variant

#### Scenario: Context prompt is forwarded to the backend

- **WHEN** an engine is asked to transcribe with options carrying a context prompt
- **THEN** the prompt reaches the backend's prompt mechanism for that run

#### Scenario: Absent prompt adds nothing to the invocation

- **WHEN** an engine is asked to transcribe with options carrying no context prompt
- **THEN** the backend invocation carries no prompt argument and behavior matches the pre-context feature


<!-- @trace
source: context-calibration-and-marketplace
updated: 2026-07-02
code:
  - Sources/BestASRKit/Models/DataModels.swift
  - Tests/BestASRKitTests/PluginTests.swift
  - Sources/BestASRKit/Context/ContextSchema.swift
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Context/PromptRenderer.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ContextTests.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - README.md
  - .claude-plugin/marketplace.json
  - Tests/BestASRKitTests/DataModelTests.swift
  - Sources/BestASRKit/CommandCore.swift
  - plugins/bestasr/skills/srt-proofread/SKILL.md
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/CLITests.swift
-->

---
### Requirement: Availability detection is graceful

`is_available()` SHALL determine whether the underlying package and runtime are usable by probing via lazy import or an equivalent runtime probe, and SHALL return false rather than raising when the package or runtime is absent. For the mlx-audio backend the probe SHALL verify that the dedicated virtual environment's python can import `mlx_audio`.

#### Scenario: Uninstalled backend reports unavailable

- **WHEN** `is_available()` is called for a backend whose underlying package is not installed
- **THEN** it returns false
- **AND** no ImportError propagates to the caller

#### Scenario: mlx-audio venv probe

- **GIVEN** the dedicated venv is absent or cannot import `mlx_audio`
- **WHEN** availability is queried for the mlx-audio backend
- **THEN** it returns false without raising


<!-- @trace
source: mlx-audio-backend-and-bcnf-store
updated: 2026-07-02
code:
  - Sources/bestasr/BestASRCommand.swift
  - Package.swift
  - Sources/BestASRKit/Corpora/CorpusRegistry.swift
  - scripts/fetch-corpora.sh
  - Sources/BestASRKit/Store/StoreTables.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Engines/mlx_worker.py
  - Sources/BestASRKit/Router/Router.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - Sources/BestASRKit/Engines/MLXAudioEngine.swift
  - Tests/BestASRKitTests/RouterTests.swift
  - .claude-plugin/marketplace.json
  - Sources/BestASRKit/Store/StoreProjection.swift
  - Tests/BestASRKitTests/ModelGridTests.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Models/ModelGrid.swift
  - Sources/BestASRKit/Store/BenchmarkStore.swift
  - README.md
  - Tests/BestASRKitTests/DataModelTests.swift
  - CHANGELOG.md
  - Sources/BestASRKit/Benchmark/BenchmarkCache.swift
  - Sources/BestASRKit/Engines/MLXWorkerProtocol.swift
  - Tests/BestASRKitTests/BenchmarkStoreTests.swift
  - Tests/BestASRKitTests/CLITests.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/MLXAudioEngineTests.swift
  - Sources/BestASRKit/Engines/CreateOnceStore.swift
  - Sources/BestASRKit/CommandCore.swift
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