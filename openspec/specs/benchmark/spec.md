# benchmark Specification

## Purpose

TBD - created by archiving change 'swift-benchmark-driven-asr'. Update Purpose after archive.

## Requirements

### Requirement: Enumerate candidate configurations

The benchmark SHALL enumerate candidate configurations as every available backend paired with each of its supported models and, per (backend, model) pair, the quantization variants the registry lists for that pair (variant availability differs per model) on this machine, skipping backends whose availability probe reports false. The caller SHALL be able to narrow candidates with explicit backend and model filters.

#### Scenario: Only available backends produce candidates

- **WHEN** the benchmark enumerates candidates while whisper.cpp is unavailable
- **THEN** no whisper.cpp candidate appears in the run list
- **AND** a note records that whisper.cpp was skipped as unavailable

#### Scenario: Explicit filters narrow the candidate set

- **WHEN** the caller passes a backend filter naming `whisperkit` and a model filter naming `large-v3-turbo`
- **THEN** only whisperkit large-v3-turbo variants are enumerated


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
### Requirement: Parse SRT reference into ground truth

The benchmark SHALL parse a SubRip (`.srt`) reference file into an ordered list of cues (index, start, end, text) and derive the ground-truth reference text by concatenating cue texts in order. A missing or unparseable reference file SHALL produce a clear error and a usage-error exit, before any transcription starts.

#### Scenario: Valid SRT yields reference text

- **WHEN** the reference file contains two cues with texts "hello" and "world"
- **THEN** parsing yields two cues in order
- **AND** the reference text is the ordered concatenation of "hello" and "world"

#### Scenario: Malformed SRT is rejected before transcription

- **WHEN** the reference file lacks any valid `HH:MM:SS,mmm --> HH:MM:SS,mmm` timecode line
- **THEN** a clear parse error is raised naming the file
- **AND** no candidate transcription is started


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
### Requirement: Compute accuracy metric selected by language

The benchmark SHALL compute an edit-distance-based error rate between the normalized hypothesis and the normalized reference: character error rate (CER) for languages written without word spacing (including `zh`, `ja`, `ko`), and word error rate (WER) with whitespace tokenization otherwise. The report SHALL name which metric kind was used. Normalization applied to both sides SHALL include Unicode NFKC, punctuation removal, fullwidth-to-halfwidth folding, lowercasing, and whitespace collapsing.

#### Scenario: Chinese audio uses CER

- **WHEN** the benchmark language is `zh`
- **THEN** the accuracy metric kind is `cer`

#### Scenario: English audio uses WER

- **WHEN** the benchmark language is `en`
- **THEN** the accuracy metric kind is `wer`

##### Example: CER on a five-character reference

- **GIVEN** normalized reference "今天天氣好" and normalized hypothesis "今天天很好"
- **WHEN** CER is computed
- **THEN** the edit distance is 1 substitution over 5 reference characters and CER = 0.2

##### Example: WER on a four-word reference

- **GIVEN** normalized reference "the cat sat down" and normalized hypothesis "the cat sat"
- **WHEN** WER is computed
- **THEN** the edit distance is 1 deletion over 4 reference words and WER = 0.25


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
### Requirement: Measure speed and memory per candidate

For each candidate the benchmark SHALL measure the real-time factor (RTF) as wall-clock transcription seconds divided by audio duration seconds, timed after a warm-up model load so that model download and first-load time are excluded from RTF and reported separately. The benchmark SHALL record an approximate peak memory figure for the transcription and state the measurement method in the report.

#### Scenario: RTF excludes model download time

- **WHEN** a candidate downloads its model before transcribing a 60-second clip in 5 wall-clock seconds of transcription time
- **THEN** the recorded RTF is 5/60
- **AND** the download time is reported separately from RTF


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
### Requirement: Rank candidates and report results

The benchmark SHALL rank successfully measured candidates by the active profile weighting over accuracy and speed and SHALL print a report table containing, per candidate: backend, model, quantization, error rate with metric kind, times-realtime, peak memory, and rank. A machine-readable JSON output mode SHALL be available.

#### Scenario: Report contains ranked rows

- **WHEN** three candidates complete measurement
- **THEN** the report lists three rows each carrying backend, model, quantization, error rate, times-realtime, peak memory, and a distinct rank

##### Example: accuracy-first ranking under the accurate profile

| Candidate                     | CER  | x-realtime | Rank (accurate profile) |
| ----------------------------- | ---- | ---------- | ----------------------- |
| whisperkit large-v3-turbo     | 0.05 | 12.0       | 1                       |
| whisper.cpp large-v3 q5       | 0.06 | 6.0        | 2                       |
| whisper.cpp small q5          | 0.15 | 20.0       | 3                       |


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
### Requirement: Persist benchmark results to a machine-local cache

The benchmark SHALL persist each measured result to a machine-local cache keyed by backend, model, quantization, and language, with each record carrying error rate, metric kind, RTF, peak memory, audio duration, measurement timestamp, chip identifier, macOS version, and app version. A new measurement for an existing key SHALL replace the prior record. The cache SHALL be consumable by the routing capability.

#### Scenario: Re-running benchmark replaces the record for the same key

- **WHEN** the same backend, model, quantization, and language combination is benchmarked twice
- **THEN** the cache holds one record for that key carrying the newer measurement timestamp


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
### Requirement: Warn-continue on per-candidate failure

When a single candidate fails (download error, transcription error, or resource exhaustion), the benchmark SHALL record the failure with its reason, emit a warning, and continue with the remaining candidates. The benchmark SHALL exit non-zero only when every candidate fails.

#### Scenario: One failing candidate does not abort the run

- **WHEN** one of three candidates fails to transcribe
- **THEN** the other two candidates are still measured and ranked
- **AND** the failed candidate is listed with its failure reason

#### Scenario: All candidates failing is a runtime failure

- **WHEN** every enumerated candidate fails
- **THEN** the benchmark exits with a non-zero status and a clear message

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
### Requirement: Measure the context-biasing delta

When a context directory is provided, the benchmark SHALL measure each candidate twice — a baseline run without the context prompt and a run with it — and report both error rates plus their delta per candidate, in the table and in the JSON output. Only the baseline record SHALL be persisted to the machine-local cache: context effects vary per audio and per document set, and cached routing data stays context-neutral.

#### Scenario: Delta appears per candidate

- **WHEN** a benchmark runs with a context directory over two candidates
- **THEN** each reported candidate carries a baseline error rate, a with-context error rate, and their delta

##### Example: biasing improves the name-heavy clip

| Candidate       | WER (baseline) | WER (ctx) | Delta  |
| --------------- | -------------- | --------- | ------ |
| whisperkit tiny | 0.25           | 0.15      | -0.10  |

#### Scenario: Cache stays context-neutral

- **WHEN** a context-enabled benchmark completes
- **THEN** the machine-local cache holds the baseline measurements only

#### Scenario: No context directory means no extra runs

- **WHEN** a benchmark runs without a context directory
- **THEN** each candidate is measured once and the report shape is unchanged from the pre-context feature

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