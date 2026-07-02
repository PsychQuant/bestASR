## MODIFIED Requirements

### Requirement: Enumerate candidate configurations

The benchmark SHALL enumerate candidate configurations from the model grid: every available backend paired with its grid rows, honoring each row's priority tier — the default sweep includes only priority-1 rows for the mlx-audio backend (existing backends' rows are priority 1) and an explicit widening flag includes all tiers. Backends whose availability probe reports false SHALL be skipped with a note. The caller SHALL be able to narrow candidates with explicit backend and model filters.

#### Scenario: Only available backends produce candidates

- **WHEN** the benchmark enumerates candidates while whisper.cpp is unavailable
- **THEN** no whisper.cpp candidate appears in the run list
- **AND** a note records that whisper.cpp was skipped as unavailable

#### Scenario: Explicit filters narrow the candidate set

- **WHEN** the caller passes a backend filter naming `whisperkit` and a model filter naming `large-v3-turbo`
- **THEN** only whisperkit large-v3-turbo variants are enumerated

#### Scenario: Priority gates the default mlx-audio sweep

- **WHEN** the benchmark enumerates with mlx-audio available and no widening flag
- **THEN** only priority-1 mlx-audio grid rows are enumerated
- **AND** passing the widening flag enumerates priority 2 and 3 rows as well

### Requirement: Persist benchmark results to a machine-local cache

The benchmark SHALL persist each measured result as an append-only measurement record in the machine-local BCNF store (per capability `benchmark-store`), keyed by model, corpus, machine, and measurement timestamp, with the record carrying metric kind, error rate, RTF, peak memory, warm-up seconds, app version, and macOS version. Consumers SHALL read the latest-per-(model, corpus, machine) projection. The store SHALL be consumable by the routing capability.

#### Scenario: Re-running benchmark supersedes via projection

- **WHEN** the same model, corpus, and machine combination is benchmarked twice
- **THEN** the measurements table holds both rows
- **AND** the latest projection exposes only the newer measurement

### Requirement: Measure the context-biasing delta

When a context directory resolves, the benchmark SHALL run a second with-context pass per candidate and report the context error rate and its delta against the baseline. The routing value SHALL remain the baseline error rate: the measurement row stores the baseline as its error rate with the with-context rate carried alongside in a separate field, and ranking SHALL never consume the with-context rate.

#### Scenario: Store rows stay routing-neutral

- **WHEN** a benchmark runs with a context directory
- **THEN** each measurement row's error rate is the baseline pass
- **AND** the with-context rate is stored in its own field, unused by ranking
