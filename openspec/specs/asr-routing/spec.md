# asr-routing Specification

## Purpose

TBD - created by archiving change 'bestasr-mvp'. Update Purpose after archive.

## Requirements

### Requirement: Honor explicit backend override with fallback

When the caller specifies an explicit backend, the router SHALL use it if available. If the requested backend is unavailable, the router SHALL fall back to the best available backend (whisperkit first, then whisper.cpp) and SHALL append a warning naming the unavailable backend.

#### Scenario: Requested backend unavailable falls back

- **WHEN** the caller requests `whisper.cpp` but it is not available
- **AND** whisperkit is available
- **THEN** the recommendation backend is `whisperkit`
- **AND** `warnings` contains an entry stating that `whisper.cpp` was requested but unavailable


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
### Requirement: Downgrade model when memory is insufficient

Within the cold-start prior, when the estimated requirement of the selected model exceeds available unified memory, the router SHALL downgrade along the chain `large-v3 → medium → small → base → tiny` until the model fits, appending a warning and a reason for each downgrade step. Measured-data rankings are not downgraded: a benchmarked candidate has already run on this machine.

#### Scenario: Insufficient unified memory downgrades from large to a smaller model

- **WHEN** the cold-start prior selects `large-v3` but available unified memory is below its estimated requirement
- **THEN** the router selects the first smaller model in the chain that fits
- **AND** `warnings` records that a larger model did not fit

##### Example: downgrade steps by available memory

| Available memory | Start model | Final model | Warnings recorded |
| ---------------- | ----------- | ----------- | ----------------- |
| fits large-v3    | large-v3    | large-v3    | 0                 |
| fits medium only | large-v3    | medium      | 1                 |
| fits small only  | large-v3    | small       | 2                 |


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
### Requirement: Produce an explainable recommendation

Every recommendation SHALL be an `ASRRecommendation` carrying `backend`, `model`, `quantization`, `profile`, `language`, `data_source` (`measured` or `cold_start_prior`), an optional `measured` summary (metric kind, error rate, and RTF when the data source is measured), a non-empty `reason` list, and a `warnings` list. When the data source is measured, at least one reason SHALL cite the measured figures.

#### Scenario: Measured recommendation cites its numbers

- **WHEN** the router recommends from benchmark data with CER 0.05 and 12x realtime
- **THEN** `data_source` is `measured`
- **AND** `reason` contains an entry citing the measured error rate and speed

#### Scenario: Cold-start recommendation is explainable without measurements

- **WHEN** the router recommends from the cold-start prior
- **THEN** `data_source` is `cold_start_prior` and `measured` is null
- **AND** `reason` contains at least one human-readable entry explaining the backend and model choice


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
### Requirement: Handle absence of any available backend

When no backend is available, the router SHALL NOT return a runnable recommendation and SHALL surface an error that lists the supported backends (whisperkit, whisper.cpp) and how to install or enable them.

#### Scenario: No backend installed

- **WHEN** neither whisperkit nor whisper.cpp reports availability
- **THEN** the router raises a clear error naming both supported backends and install guidance


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
### Requirement: Rank candidates by measured benchmark data

The router SHALL rank candidates by measured benchmark data across every runnable backend — bundled engines and registered external engines alike — regardless of model family. Before ranking, measurements SHALL be aggregated per candidate and language: error rate and realtime factor are the equal-weight means over the candidate's measurements for that language (the store projection collapses per-candidate-per-language history by mean, and the router's own aggregation — keyed with language so cross-metric averaging can never occur — defends any raw-record path), so a single flattering measurement on a short corpus can never outrank a broadly measured candidate. An aggregated candidate whose mean error rate exceeds 0.5 SHALL be excluded from autonomous ranking (more than half wrong has negative practical value); if exclusion empties the pool the router falls back to the cold-start prior, and an explicitly locked backend bypasses the floor with a quality warning in the reasons. Catalog rows whose backend has neither a bundled engine nor a registered, available external adapter SHALL remain excluded from enumeration (reference-only, unchanged from #20); registering an adapter (#51) is what upgrades those rows to candidates.

#### Scenario: Cross-family candidate wins on merit

- **WHEN** measured records show a fluid-parakeet model outperforming every Whisper variant for the requested language under the active profile
- **THEN** `recommend` returns the fluid-parakeet candidate as the top choice with its measured evidence

#### Scenario: Family with no coverage for the language loses naturally

- **WHEN** the requested language has no (or poor) measured results for fluid-parakeet but strong Whisper results
- **THEN** the router ranks the Whisper candidate first — family diversity never overrides measured evidence

#### Scenario: Unregistered reference rows still never enumerate

- **WHEN** candidates are enumerated on a machine with no external-engine registry entry for mlx-audio
- **THEN** mlx-audio reference rows remain excluded, unchanged from #20

#### Scenario: A registered external backend enumerates its rows

- **WHEN** the registry enables `mlx-audio` with an existing executable
- **THEN** mlx-audio catalog rows enumerate as candidates and rank purely on measured evidence (the cold-start prior still never proposes an unmeasured family)

#### Scenario: A single flattering measurement never outranks the aggregate

- **WHEN** one candidate carries a single 0.0-error record on a short corpus while another carries many records averaging 0.09 on real corpora, and the first candidate's own mean over all its records is worse
- **THEN** ranking uses each candidate's mean, and the broadly measured candidate wins

#### Scenario: A candidate below the quality floor is never autonomously recommended

- **WHEN** a candidate's mean error rate for the requested language is 0.93
- **THEN** it is excluded from autonomous ranking even if it is the fastest
- **AND** a candidate within the floor is recommended instead

#### Scenario: The floor never strands the router

- **WHEN** every measured candidate for the language exceeds the floor
- **THEN** the router falls back to the cold-start prior as if unmeasured

#### Scenario: An explicit backend lock bypasses the floor with a warning

- **WHEN** the user locks a backend whose mean error rate exceeds the floor
- **THEN** the route succeeds on that backend and the reasons carry a quality warning


<!-- @trace
source: routing-quality-floor
updated: 2026-07-07
code:
  - Sources/BestASRKit/Router/Router.swift
  - Sources/BestASRKit/Store/StoreProjection.swift
  - Tests/BestASRKitTests/RouterTests.swift
  - Tests/BestASRKitTests/BenchmarkStoreTests.swift
  - CHANGELOG.md
-->


### Requirement: Cold-start prior when no benchmark data exists

When no usable benchmark record exists for the request, the router SHALL fall back to a static prior: select the preferred available backend (whisperkit first, then whisper.cpp), select the most accurate model in the active profile's candidate list (`low` → tiny/base/small, `medium` → small/medium, `high` / `xhigh` / `max` → medium/large-v3-turbo/large-v3 — the top three tiers share one list because without measured data the ordinals can only differ in measured weighting) whose estimated memory requirement fits unified memory, and mark the recommendation data source as cold-start prior. The reasons SHALL include a suggestion to run the benchmark command for measured, machine-specific recommendations.

#### Scenario: Cold start recommends from the prior and suggests benchmarking

- **WHEN** the benchmark cache is empty and whisperkit is available
- **AND** the profile is `medium`
- **THEN** the recommendation backend is `whisperkit` with a model from the medium candidate list
- **AND** the recommendation data source is `cold_start_prior`
- **AND** `reason` contains an entry suggesting to run the benchmark command
