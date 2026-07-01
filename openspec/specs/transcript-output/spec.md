# transcript-output Specification

## Purpose

TBD - created by archiving change 'bestasr-mvp'. Update Purpose after archive.

## Requirements

### Requirement: Write plain text output

The system SHALL write a `Transcript` as plain text containing the full transcript text.

#### Scenario: txt output contains transcript text

- **WHEN** a `Transcript` is written with format `txt`
- **THEN** the output file contains the transcript text


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
### Requirement: Write JSON output

The system SHALL write a `Transcript` as JSON containing `text`, `language`, `duration`, `backend`, `model`, and a `segments` array where each element has `id`, `start`, `end`, `text`, and `confidence`.

#### Scenario: json output is parseable and complete

- **WHEN** a `Transcript` is written with format `json`
- **THEN** the output parses as JSON
- **AND** it contains the top-level keys `text`, `language`, `duration`, `backend`, `model`, and `segments`


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
### Requirement: Write SRT subtitles

The system SHALL write a `Transcript` as SubRip (SRT) with 1-based sequential indices and timecodes formatted as `HH:MM:SS,mmm` using a comma decimal separator and a `-->` range separator.

#### Scenario: srt entries use comma millisecond separator

- **WHEN** a `Transcript` is written with format `srt`
- **THEN** each cue is a sequential index, a `start --> end` timecode line, and the segment text

##### Example: single segment rendered as SRT

- **GIVEN** a segment with id=1, start=0.0, end=2.5, text="hello world"
- **WHEN** it is written as SRT
- **THEN** the cue is:

```
1
00:00:00,000 --> 00:00:02,500
hello world
```


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
### Requirement: Write WebVTT subtitles

The system SHALL write a `Transcript` as WebVTT beginning with a `WEBVTT` header and timecodes formatted as `HH:MM:SS.mmm` using a dot decimal separator.

#### Scenario: vtt starts with header and uses dot separator

- **WHEN** a `Transcript` is written with format `vtt`
- **THEN** the first line is `WEBVTT`
- **AND** each cue timecode uses a dot before the milliseconds

##### Example: single segment rendered as VTT

- **GIVEN** a segment with start=0.0, end=2.5, text="hello world"
- **WHEN** it is written as VTT
- **THEN** the body cue is:

```
00:00:00.000 --> 00:00:02.500
hello world
```


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
### Requirement: Select writer by format with a default

The system SHALL select the output writer by an explicit format argument, defaulting to `txt` when no format is given. An unsupported format SHALL raise a clear error listing the supported formats.

#### Scenario: default format is txt

- **WHEN** a `Transcript` is written with no format specified
- **THEN** the writer used is the plain text writer

#### Scenario: unsupported format is rejected

- **WHEN** a format outside `txt`, `json`, `srt`, `vtt` is requested
- **THEN** a clear error is raised naming the supported formats

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