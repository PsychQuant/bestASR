# cli — delta

## MODIFIED Requirements

### Requirement: transcribe command with options

`bestasr transcribe <audio>` SHALL transcribe the input and write the result in the requested format, honoring `--profile`, `--backend`, `--model`, `--language`, `--format`, `--output`, and `--context-dir`. When `--format` is omitted it SHALL default to `txt`; when `--output` is omitted the output path SHALL derive from the input file base name and the format extension; when `--context-dir` is omitted the context directory SHALL resolve per the context-calibration three-layer precedence. `--profile` accepts the ordinal ladder `low` / `medium` / `high` / `xhigh` / `max` and defaults to `auto`: `auto` SHALL resolve to `medium`, or to `low` when the machine reports pressure (thermal state serious/critical, or Low Power Mode), and the resolution SHALL be disclosed in the explain reasons. An explicitly passed ordinal SHALL never be altered by machine pressure. A legacy profile value (`fast`, `balanced`, `accurate`) SHALL fail with an error that names its ordinal replacement.

#### Scenario: transcribe writes requested format

- **WHEN** the user runs `bestasr transcribe input.mp3 --format srt`
- **THEN** an SRT file is written for the transcript

#### Scenario: defaults apply when options are omitted

- **WHEN** the user runs `bestasr transcribe input.mp3` on an unpressured machine
- **THEN** the profile resolves to `medium` (from `auto`), the format is `txt`, and backend, model, and language are chosen automatically

#### Scenario: auto downshifts under machine pressure and says so

- **WHEN** the user runs `bestasr transcribe input.mp3` while the machine reports thermal pressure or Low Power Mode
- **THEN** the profile resolves to `low`
- **AND** the explain reasons disclose the downshift and its cause

#### Scenario: an explicit ordinal ignores machine pressure

- **WHEN** the user runs `bestasr transcribe input.mp3 --profile max` while the machine reports pressure
- **THEN** the profile is `max` (no downshift)

#### Scenario: legacy profile values fail with a migration hint

- **WHEN** the user runs `bestasr transcribe input.mp3 --profile balanced`
- **THEN** the command fails and the error names `medium` as the replacement

#### Scenario: explicit context directory feeds the transcription

- **WHEN** the user runs `bestasr transcribe input.mp3 --context-dir ./ctx` and `./ctx` contains context values
- **THEN** the rendered context prompt is injected into that transcription run
