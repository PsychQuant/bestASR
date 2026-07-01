## ADDED Requirements

### Requirement: benchmark command

`bestasr benchmark <audio> --reference <ground_truth.srt>` SHALL run the benchmark capability over the enumerated candidates, print the ranked report table to standard output, and persist results to the machine-local cache. The command SHALL honor `--language`, backend and model filter options, and a `--json` mode emitting machine-readable results. A missing or unparseable reference file SHALL exit with a usage-error status before any transcription; all candidates failing SHALL exit with a runtime-failure status.

#### Scenario: Benchmark prints a ranked table and persists results

- **WHEN** the user runs `bestasr benchmark clip.wav --reference clip.srt` with at least one available backend
- **THEN** a ranked report table is printed
- **AND** the measured results are persisted to the machine-local cache

#### Scenario: Missing reference is a usage error

- **WHEN** the user runs `bestasr benchmark clip.wav --reference missing.srt` and the file does not exist
- **THEN** a clear error is printed and the process exits with a usage-error status
- **AND** no transcription is started

## MODIFIED Requirements

### Requirement: Provide help and a stable command surface

The `bestasr` CLI SHALL expose the subcommands `diagnose`, `recommend`, `transcribe`, `benchmark`, `list-backends`, and `list-models`, and SHALL print usage and exit with status 0 when invoked with `--help`.

#### Scenario: help lists subcommands

- **WHEN** the user runs `bestasr --help`
- **THEN** usage text lists the six subcommands and the process exits with status 0

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
