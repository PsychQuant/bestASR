## MODIFIED Requirements

### Requirement: Enumerate candidate configurations

The benchmark SHALL enumerate candidate configurations from the model grid: every available backend paired with its grid rows. Backends whose availability probe reports false SHALL be skipped with a note; grid rows whose backend has no bundled engine (the mlx-audio reference catalog) SHALL NOT be enumerated. The caller SHALL be able to narrow candidates with explicit backend and model filters.

#### Scenario: Only available backends produce candidates

- **WHEN** the benchmark enumerates candidates while whisper.cpp is unavailable
- **THEN** no whisper.cpp candidate appears in the run list
- **AND** a note records that whisper.cpp was skipped as unavailable

#### Scenario: Explicit filters narrow the candidate set

- **WHEN** the caller passes a backend filter naming `whisperkit` and a model filter naming `large-v3-turbo`
- **THEN** only whisperkit large-v3-turbo variants are enumerated

#### Scenario: Reference rows never enumerate

- **WHEN** the benchmark enumerates with no filters
- **THEN** no mlx-audio reference row appears among the candidates
