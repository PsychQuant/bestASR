## ADDED Requirements

### Requirement: Common engine interface

Every backend SHALL implement the `BaseEngine` interface with `is_available() -> bool`, `transcribe(audio_path, options) -> Transcript`, and `estimate_requirements(model_name) -> ModelRequirements`. The MVP SHALL provide implementations for `faster-whisper`, `whisper.cpp`, and `mlx-whisper`.

#### Scenario: Each backend exposes the interface

- **WHEN** any supported backend class is instantiated
- **THEN** it provides `is_available`, `transcribe`, and `estimate_requirements` with the specified signatures

### Requirement: Availability detection is graceful

`is_available()` SHALL determine whether the underlying package and runtime are usable by probing via lazy import, and SHALL return false rather than raising when the package or runtime is absent.

#### Scenario: Uninstalled backend reports unavailable

- **WHEN** `is_available()` is called for a backend whose underlying package is not installed
- **THEN** it returns false
- **AND** no ImportError propagates to the caller

### Requirement: Transcription returns a normalized Transcript

`transcribe` SHALL return a `Transcript` carrying `text`, `language`, `duration`, an ordered list of `TranscriptSegment`, and the `backend` and `model` used. Each `TranscriptSegment` SHALL carry `id`, `start`, `end`, `text`, and an optional `confidence`.

#### Scenario: Transcript carries segments and metadata

- **WHEN** a backend transcribes an audio file successfully
- **THEN** the returned `Transcript` has non-null `text`, a `segments` list ordered by `start`, and `backend` and `model` set to the values used

### Requirement: Estimate model requirements

`estimate_requirements(model_name)` SHALL return the estimated memory footprint used by the router to decide feasibility and downgrades, sourced from a static requirements table.

#### Scenario: Requirement estimate available for each model size

- **WHEN** `estimate_requirements` is called for a supported model name
- **THEN** it returns a `ModelRequirements` value with a positive estimated memory figure

### Requirement: Transcription failure is surfaced

When a backend fails to transcribe (for example a decode error or a missing runtime dependency such as ffmpeg), it SHALL raise a clear, typed error rather than returning an empty or partial `Transcript` silently.

#### Scenario: Decode failure raises

- **WHEN** `transcribe` is given an unreadable or unsupported audio input
- **THEN** a clear error is raised describing the failure
