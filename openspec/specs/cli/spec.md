# cli Specification

## Purpose

TBD - created by archiving change 'bestasr-mvp'. Update Purpose after archive.

## Requirements

### Requirement: Provide help and a stable command surface

The `bestasr` CLI SHALL expose the subcommands `diagnose`, `recommend`, `transcribe`, `benchmark`, `list-backends`, and `list-models`, and SHALL print usage and exit with status 0 when invoked with `--help`.

#### Scenario: help lists subcommands

- **WHEN** the user runs `bestasr --help`
- **THEN** usage text lists the six subcommands and the process exits with status 0


<!-- @trace
source: swift-benchmark-driven-asr
updated: 2026-07-02
code:
  - archive/python/pyproject.toml
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Detect/Language.swift
  - archive/python/bestasr/detect/acceleration.py
  - bestasr/utils/__init__.py
  - bestasr/detect/language.py
  - bestasr/router/recommendation.py
  - bestasr/engines/__init__.py
  - Sources/BestASRKit/Models/DataModels.swift
  - bestasr/output/_timecode.py
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - tests/conftest.py
  - archive/python/bestasr/detect/__init__.py
  - archive/python/bestasr/router/recommendation.py
  - bestasr/detect/system.py
  - bestasr/router/profiles.py
  - bestasr/output/json_writer.py
  - Sources/BestASRKit/Router/ColdStartPrior.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - bestasr/router/scorer.py
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - bestasr/output/vtt.py
  - bestasr/output/__init__.py
  - Tests/BestASRKitTests/TestSupport.swift
  - archive/python/bestasr/utils/__init__.py
  - archive/python/bestasr/detect/system.py
  - archive/python/bestasr/router/rules.py
  - pyproject.toml
  - Sources/BestASRKit/Router/Ranking.swift
  - bestasr/detect/audio.py
  - bestasr/utils/ffmpeg.py
  - archive/python/bestasr/output/vtt.py
  - archive/python/bestasr/output/srt.py
  - Sources/BestASRKit/CommandCore.swift
  - Package.swift
  - archive/python/bestasr/models/requirements.py
  - Sources/BestASRKit/Detect/SystemDetector.swift
  - archive/python/bestasr/engines/whisper_cpp_engine.py
  - bestasr/router/__init__.py
  - examples/recommend.sh
  - examples/basic_transcribe.sh
  - Tests/BestASRKitTests/EngineTests.swift
  - Tests/BestASRKitTests/OutputTests.swift
  - archive/python/bestasr/detect/audio.py
  - Sources/BestASRKit/Engines/Engine.swift
  - Tests/BestASRKitTests/MetricsTests.swift
  - archive/python/bestasr/models/registry.py
  - bestasr/router/rules.py
  - archive/python/bestasr/engines/mlx_whisper_engine.py
  - bestasr/engines/faster_whisper_engine.py
  - bestasr/detect/hardware.py
  - bestasr/output/txt.py
  - bestasr/engines/base.py
  - Sources/BestASRKit/Benchmark/SRTParser.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Package.resolved
  - bestasr/output/srt.py
  - bestasr/models/__init__.py
  - archive/python/bestasr/detect/language.py
  - archive/python/bestasr/output/__init__.py
  - Sources/BestASRKit/Router/Router.swift
  - bestasr/detect/__init__.py
  - archive/python/bestasr/__init__.py
  - Tests/BestASRKitTests/CLITests.swift
  - Sources/BestASRKit/Benchmark/TextNormalizer.swift
  - archive/python/bestasr/detect/hardware.py
  - archive/python/bestasr/output/json_writer.py
  - Sources/BestASRKit/Benchmark/ErrorRate.swift
  - archive/python/bestasr/router/profiles.py
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - bestasr/detect/acceleration.py
  - bestasr/cli.py
  - Tests/BestASRKitTests/RouterTests.swift
  - archive/python/bestasr/cli.py
  - archive/python/bestasr/engines/base.py
  - archive/python/bestasr/models/__init__.py
  - archive/python/examples/diagnose.sh
  - archive/python/bestasr/engines/faster_whisper_engine.py
  - Sources/BestASRKit/Detect/AudioProber.swift
  - archive/python/bestasr/engines/__init__.py
  - archive/python/examples/recommend.sh
  - bestasr/models/requirements.py
  - archive/python/bestasr/utils/ffmpeg.py
  - archive/python/bestasr/router/__init__.py
  - archive/python/bestasr/output/_timecode.py
  - bestasr/engines/mlx_whisper_engine.py
  - bestasr/engines/whisper_cpp_engine.py
  - Sources/BestASRKit/Output/TranscriptWriter.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - examples/diagnose.sh
  - Tests/BestASRKitTests/DetectionTests.swift
  - archive/python/bestasr/router/scorer.py
  - archive/python/examples/basic_transcribe.sh
  - bestasr/models/registry.py
  - archive/python/bestasr/output/txt.py
  - Sources/BestASRKit/Benchmark/BenchmarkCache.swift
  - Tests/BestASRKitTests/DataModelTests.swift
  - bestasr/__init__.py
  - Sources/bestasr/BestASRCommand.swift
  - README.md
tests:
  - tests/test_engines.py
  - archive/python/tests/conftest.py
  - tests/test_dataclasses.py
  - archive/python/tests/test_fixtures.py
  - tests/test_readme_examples.py
  - archive/python/tests/test_cli.py
  - archive/python/tests/test_hardware_detection.py
  - tests/test_router.py
  - archive/python/tests/test_readme_examples.py
  - archive/python/tests/test_router.py
  - tests/test_audio_detection.py
  - tests/test_hardware_detection.py
  - archive/python/tests/test_audio_detection.py
  - archive/python/tests/test_output_formats.py
  - tests/test_fixtures.py
  - tests/test_cli.py
  - tests/test_output_formats.py
  - archive/python/tests/test_dataclasses.py
  - archive/python/tests/test_engines.py
-->

---
### Requirement: diagnose command

`bestasr diagnose` SHALL run system detection and print the detected environment together with a recommendation and its reasons, without requiring an audio file, exiting 0 on success.

#### Scenario: diagnose prints environment and recommendation

- **WHEN** the user runs `bestasr diagnose`
- **THEN** the output includes system facts and a recommended backend, model, compute type, and reasons
- **AND** the process exits with status 0


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
### Requirement: recommend command emits JSON only

`bestasr recommend <audio>` SHALL print exactly one JSON object describing the recommendation to standard output and SHALL NOT run transcription, exiting 0 on success. The JSON SHALL contain `backend`, `model`, `quantization`, `data_source` (`measured` or `cold_start_prior`), a `measured` field carrying metric kind, error rate, and RTF when the data source is measured (null otherwise), and `reason`.

#### Scenario: recommend output is machine-readable

- **WHEN** the user runs `bestasr recommend sample.wav`
- **THEN** standard output is a single JSON object containing `backend`, `model`, `quantization`, `data_source`, `measured`, and `reason`
- **AND** no transcript is produced

#### Scenario: recommend reflects benchmark data when present

- **WHEN** the machine-local cache holds a usable benchmark record and the user runs `bestasr recommend sample.wav`
- **THEN** the JSON `data_source` is `measured`
- **AND** `measured` carries the metric kind, error rate, and RTF of the recommended candidate


<!-- @trace
source: swift-benchmark-driven-asr
updated: 2026-07-02
code:
  - archive/python/pyproject.toml
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Detect/Language.swift
  - archive/python/bestasr/detect/acceleration.py
  - bestasr/utils/__init__.py
  - bestasr/detect/language.py
  - bestasr/router/recommendation.py
  - bestasr/engines/__init__.py
  - Sources/BestASRKit/Models/DataModels.swift
  - bestasr/output/_timecode.py
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - tests/conftest.py
  - archive/python/bestasr/detect/__init__.py
  - archive/python/bestasr/router/recommendation.py
  - bestasr/detect/system.py
  - bestasr/router/profiles.py
  - bestasr/output/json_writer.py
  - Sources/BestASRKit/Router/ColdStartPrior.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - bestasr/router/scorer.py
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - bestasr/output/vtt.py
  - bestasr/output/__init__.py
  - Tests/BestASRKitTests/TestSupport.swift
  - archive/python/bestasr/utils/__init__.py
  - archive/python/bestasr/detect/system.py
  - archive/python/bestasr/router/rules.py
  - pyproject.toml
  - Sources/BestASRKit/Router/Ranking.swift
  - bestasr/detect/audio.py
  - bestasr/utils/ffmpeg.py
  - archive/python/bestasr/output/vtt.py
  - archive/python/bestasr/output/srt.py
  - Sources/BestASRKit/CommandCore.swift
  - Package.swift
  - archive/python/bestasr/models/requirements.py
  - Sources/BestASRKit/Detect/SystemDetector.swift
  - archive/python/bestasr/engines/whisper_cpp_engine.py
  - bestasr/router/__init__.py
  - examples/recommend.sh
  - examples/basic_transcribe.sh
  - Tests/BestASRKitTests/EngineTests.swift
  - Tests/BestASRKitTests/OutputTests.swift
  - archive/python/bestasr/detect/audio.py
  - Sources/BestASRKit/Engines/Engine.swift
  - Tests/BestASRKitTests/MetricsTests.swift
  - archive/python/bestasr/models/registry.py
  - bestasr/router/rules.py
  - archive/python/bestasr/engines/mlx_whisper_engine.py
  - bestasr/engines/faster_whisper_engine.py
  - bestasr/detect/hardware.py
  - bestasr/output/txt.py
  - bestasr/engines/base.py
  - Sources/BestASRKit/Benchmark/SRTParser.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Package.resolved
  - bestasr/output/srt.py
  - bestasr/models/__init__.py
  - archive/python/bestasr/detect/language.py
  - archive/python/bestasr/output/__init__.py
  - Sources/BestASRKit/Router/Router.swift
  - bestasr/detect/__init__.py
  - archive/python/bestasr/__init__.py
  - Tests/BestASRKitTests/CLITests.swift
  - Sources/BestASRKit/Benchmark/TextNormalizer.swift
  - archive/python/bestasr/detect/hardware.py
  - archive/python/bestasr/output/json_writer.py
  - Sources/BestASRKit/Benchmark/ErrorRate.swift
  - archive/python/bestasr/router/profiles.py
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - bestasr/detect/acceleration.py
  - bestasr/cli.py
  - Tests/BestASRKitTests/RouterTests.swift
  - archive/python/bestasr/cli.py
  - archive/python/bestasr/engines/base.py
  - archive/python/bestasr/models/__init__.py
  - archive/python/examples/diagnose.sh
  - archive/python/bestasr/engines/faster_whisper_engine.py
  - Sources/BestASRKit/Detect/AudioProber.swift
  - archive/python/bestasr/engines/__init__.py
  - archive/python/examples/recommend.sh
  - bestasr/models/requirements.py
  - archive/python/bestasr/utils/ffmpeg.py
  - archive/python/bestasr/router/__init__.py
  - archive/python/bestasr/output/_timecode.py
  - bestasr/engines/mlx_whisper_engine.py
  - bestasr/engines/whisper_cpp_engine.py
  - Sources/BestASRKit/Output/TranscriptWriter.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - examples/diagnose.sh
  - Tests/BestASRKitTests/DetectionTests.swift
  - archive/python/bestasr/router/scorer.py
  - archive/python/examples/basic_transcribe.sh
  - bestasr/models/registry.py
  - archive/python/bestasr/output/txt.py
  - Sources/BestASRKit/Benchmark/BenchmarkCache.swift
  - Tests/BestASRKitTests/DataModelTests.swift
  - bestasr/__init__.py
  - Sources/bestasr/BestASRCommand.swift
  - README.md
tests:
  - tests/test_engines.py
  - archive/python/tests/conftest.py
  - tests/test_dataclasses.py
  - archive/python/tests/test_fixtures.py
  - tests/test_readme_examples.py
  - archive/python/tests/test_cli.py
  - archive/python/tests/test_hardware_detection.py
  - tests/test_router.py
  - archive/python/tests/test_readme_examples.py
  - archive/python/tests/test_router.py
  - tests/test_audio_detection.py
  - tests/test_hardware_detection.py
  - archive/python/tests/test_audio_detection.py
  - archive/python/tests/test_output_formats.py
  - tests/test_fixtures.py
  - tests/test_cli.py
  - tests/test_output_formats.py
  - archive/python/tests/test_dataclasses.py
  - archive/python/tests/test_engines.py
-->

---
### Requirement: transcribe command with options

`bestasr transcribe <audio>` SHALL transcribe the input and write the result in the requested format, honoring `--profile`, `--backend`, `--model`, `--language`, `--format`, `--output`, and `--context-dir`. When `--format` is omitted it SHALL default to `txt`; when `--output` is omitted the output path SHALL derive from the input file base name and the format extension; when `--context-dir` is omitted the context directory SHALL resolve per the context-calibration three-layer precedence.

#### Scenario: transcribe writes requested format

- **WHEN** the user runs `bestasr transcribe input.mp3 --format srt`
- **THEN** an SRT file is written for the transcript

#### Scenario: defaults apply when options are omitted

- **WHEN** the user runs `bestasr transcribe input.mp3`
- **THEN** the profile is `balanced`, the format is `txt`, and backend, model, and language are chosen automatically

#### Scenario: explicit context directory feeds the transcription

- **WHEN** the user runs `bestasr transcribe input.mp3 --context-dir ./ctx` and `./ctx` contains context values
- **THEN** the rendered context prompt is injected into that transcription run


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
### Requirement: explain mode surfaces reasoning

When `--explain` is passed to `transcribe`, the CLI SHALL additionally output the recommendation `reason` and `warnings`, and — when a context directory was resolved — the context usage disclosure (resolved directory, injected values, truncated items, ignored files). Diagnostic reasoning SHALL NOT contaminate the transcript output file.

#### Scenario: explain prints reasons alongside transcription

- **WHEN** the user runs `bestasr transcribe input.mp3 --explain`
- **THEN** the recommendation reasons and any warnings are printed to the user
- **AND** the written transcript file contains only the transcript

#### Scenario: explain includes the context disclosure when context was used

- **WHEN** the user runs `bestasr transcribe input.mp3 --explain` with a resolved context directory
- **THEN** the explain output includes the resolved directory, the injected values, any truncated items, and any ignored files


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
### Requirement: list-backends and list-models

`bestasr list-backends` SHALL list supported backends with their availability, and `bestasr list-models` SHALL list supported model sizes.

#### Scenario: list-backends shows availability

- **WHEN** the user runs `bestasr list-backends`
- **THEN** each supported backend is listed with whether it is available on this machine


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
### Requirement: Non-zero exit on failure

The CLI SHALL exit with a non-zero status and print a clear message when the audio file is missing, the format is unsupported, or no backend is available.

#### Scenario: missing audio file fails clearly

- **WHEN** the user runs `bestasr transcribe missing.mp3` and the file does not exist
- **THEN** a clear error is printed and the process exits with a non-zero status

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
### Requirement: benchmark command

`bestasr benchmark <audio> --reference <ground_truth.srt>` SHALL run the benchmark capability over the enumerated candidates, print the ranked report table to standard output, and persist results to the machine-local cache. The command SHALL honor `--language`, backend and model filter options, an optional `--context-dir` enabling the context-biasing delta measurement, and a `--json` mode emitting machine-readable results. A missing or unparseable reference file SHALL exit with a usage-error status before any transcription; all candidates failing SHALL exit with a runtime-failure status.

#### Scenario: Benchmark prints a ranked table and persists results

- **WHEN** the user runs `bestasr benchmark clip.wav --reference clip.srt` with at least one available backend
- **THEN** a ranked report table is printed
- **AND** the measured results are persisted to the machine-local cache

#### Scenario: Missing reference is a usage error

- **WHEN** the user runs `bestasr benchmark clip.wav --reference missing.srt` and the file does not exist
- **THEN** a clear error is printed and the process exits with a usage-error status
- **AND** no transcription is started

#### Scenario: Context flag turns on the delta columns

- **WHEN** the user runs `bestasr benchmark clip.wav --reference clip.srt --context-dir ./ctx`
- **THEN** the report carries both the baseline and with-context error rates and their delta

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