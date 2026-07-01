# system-detection Specification

## Purpose

TBD - created by archiving change 'bestasr-mvp'. Update Purpose after archive.

## Requirements

### Requirement: Probe audio file properties

The system SHALL probe an audio file for duration, container format, sample rate, and channel count, exposed on `AudioInfo`, using the platform audio framework (AVFoundation) as the source. An unreadable or non-audio file SHALL produce a clear error naming the file.

#### Scenario: Probe a valid audio file

- **WHEN** `AudioInfo` is built for a valid audio file
- **THEN** `duration`, `format`, `sample_rate`, and `channels` are populated with values read from the file

#### Scenario: Unreadable file is rejected clearly

- **WHEN** `AudioInfo` is built for a file that is missing or not decodable as audio
- **THEN** a clear error is raised naming the file


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
### Requirement: Determine transcription language

The system SHALL record the requested language on `AudioInfo.language`. When the caller passes an explicit language it SHALL be used verbatim. When the caller passes `auto`, `AudioInfo.language` SHALL be null and language detection SHALL be deferred to the engine.

#### Scenario: Explicit language is recorded

- **WHEN** the caller requests language `zh`
- **THEN** `AudioInfo.language` equals `zh`

#### Scenario: Auto language defers to engine

- **WHEN** the caller requests language `auto`
- **THEN** `AudioInfo.language` is null


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
### Requirement: Detect Apple Silicon hardware profile

The system SHALL detect the Apple chip name, total unified memory in gigabytes, Apple Neural Engine availability, and the macOS version, exposed on `SystemInfo` as `chip`, `unified_memory_gb`, `has_ane`, and `macos_version`. Detection SHALL use system facilities (sysctl and process information APIs) with no external tool dependency. When ANE availability cannot be determined for an unknown chip generation, the system SHALL report it as unknown rather than failing. When run on a non-Apple-Silicon host (including under Rosetta translation), the system SHALL fail with a clear unsupported-platform error.

#### Scenario: Report chip and unified memory on Apple Silicon

- **WHEN** detection runs on an Apple Silicon Mac
- **THEN** `SystemInfo.chip` is a non-empty string naming the Apple chip
- **AND** `SystemInfo.unified_memory_gb` is a positive number
- **AND** `SystemInfo.macos_version` reflects the running macOS version

#### Scenario: Unknown chip generation degrades ANE to unknown

- **WHEN** detection runs on a chip generation absent from the ANE capability table
- **THEN** `has_ane` reports an unknown state
- **AND** detection completes without raising

#### Scenario: Non-Apple-Silicon host is rejected clearly

- **WHEN** detection runs on a non-Apple-Silicon host
- **THEN** a clear unsupported-platform error is raised naming the requirement for Apple Silicon

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