## MODIFIED Requirements

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

### Requirement: explain mode surfaces reasoning

When `--explain` is passed to `transcribe`, the CLI SHALL additionally output the recommendation `reason` and `warnings`, and — when a context directory was resolved — the context usage disclosure (resolved directory, injected values, truncated items, ignored files). Diagnostic reasoning SHALL NOT contaminate the transcript output file.

#### Scenario: explain prints reasons alongside transcription

- **WHEN** the user runs `bestasr transcribe input.mp3 --explain`
- **THEN** the recommendation reasons and any warnings are printed to the user
- **AND** the written transcript file contains only the transcript

#### Scenario: explain includes the context disclosure when context was used

- **WHEN** the user runs `bestasr transcribe input.mp3 --explain` with a resolved context directory
- **THEN** the explain output includes the resolved directory, the injected values, any truncated items, and any ignored files

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
