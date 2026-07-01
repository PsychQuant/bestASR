## ADDED Requirements

### Requirement: Provide help and a stable command surface

The `bestasr` CLI SHALL expose the subcommands `diagnose`, `recommend`, `transcribe`, `list-backends`, and `list-models`, and SHALL print usage and exit with status 0 when invoked with `--help`.

#### Scenario: help lists subcommands

- **WHEN** the user runs `bestasr --help`
- **THEN** usage text lists the subcommands and the process exits with status 0

### Requirement: diagnose command

`bestasr diagnose` SHALL run system detection and print the detected environment together with a recommendation and its reasons, without requiring an audio file, exiting 0 on success.

#### Scenario: diagnose prints environment and recommendation

- **WHEN** the user runs `bestasr diagnose`
- **THEN** the output includes system facts and a recommended backend, model, compute type, and reasons
- **AND** the process exits with status 0

### Requirement: recommend command emits JSON only

`bestasr recommend <audio>` SHALL print exactly one JSON object describing the recommendation to standard output and SHALL NOT run transcription, exiting 0 on success.

#### Scenario: recommend output is machine-readable

- **WHEN** the user runs `bestasr recommend sample.wav`
- **THEN** standard output is a single JSON object containing `backend`, `model`, `compute_type`, and `reason`
- **AND** no transcript is produced

### Requirement: transcribe command with options

`bestasr transcribe <audio>` SHALL transcribe the input and write the result in the requested format, honoring `--profile`, `--backend`, `--model`, `--language`, `--format`, and `--output`. When `--format` is omitted it SHALL default to `txt`; when `--output` is omitted the output path SHALL derive from the input file base name and the format extension.

#### Scenario: transcribe writes requested format

- **WHEN** the user runs `bestasr transcribe input.mp3 --format srt`
- **THEN** an SRT file is written for the transcript

#### Scenario: defaults apply when options are omitted

- **WHEN** the user runs `bestasr transcribe input.mp3`
- **THEN** the profile is `balanced`, the format is `txt`, and backend, model, and language are chosen automatically

### Requirement: explain mode surfaces reasoning

When `--explain` is passed to `transcribe`, the CLI SHALL additionally output the recommendation `reason` and `warnings`. Diagnostic reasoning SHALL NOT contaminate the transcript output file.

#### Scenario: explain prints reasons alongside transcription

- **WHEN** the user runs `bestasr transcribe input.mp3 --explain`
- **THEN** the recommendation reasons and any warnings are printed to the user
- **AND** the written transcript file contains only the transcript

### Requirement: list-backends and list-models

`bestasr list-backends` SHALL list supported backends with their availability, and `bestasr list-models` SHALL list supported model sizes.

#### Scenario: list-backends shows availability

- **WHEN** the user runs `bestasr list-backends`
- **THEN** each supported backend is listed with whether it is available on this machine

### Requirement: Non-zero exit on failure

The CLI SHALL exit with a non-zero status and print a clear message when the audio file is missing, the format is unsupported, or no backend is available.

#### Scenario: missing audio file fails clearly

- **WHEN** the user runs `bestasr transcribe missing.mp3` and the file does not exist
- **THEN** a clear error is printed and the process exits with a non-zero status
