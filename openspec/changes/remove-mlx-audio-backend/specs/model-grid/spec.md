## MODIFIED Requirements

### Requirement: Full-family catalog

The model grid SHALL enumerate the runnable backends' models as catalog rows and SHALL additionally retain the 15 mlx-audio STT families as a **reference catalog** — rows carrying languages, estimated memory, optional HF repo id with pinned revision, and a historical priority tier. Reference rows are not runnable (no engine is bundled for them) and exist for lookup and potential future reinstatement.

#### Scenario: grid completeness

- **WHEN** the grid is loaded
- **THEN** it contains rows for all 15 mlx-audio families (reference) plus the WhisperKit and whisper.cpp models, totalling at least 30 rows

#### Scenario: reference rows are visible but not runnable

- **WHEN** the model listing renders
- **THEN** the mlx-audio section is labeled as a reference catalog whose backend is not bundled
- **AND** benchmark enumeration produces no candidates from reference rows

### Requirement: Priority tiers gate the default sweep

Grid rows SHALL carry priority 1, 2, or 3. For runnable backends every current row is priority 1 and enumerates by default; for the mlx-audio reference catalog the tier is retained as historical metadata (the original first-run/representative/deferred selection) and has no enumeration effect.

#### Scenario: default sweep

- **WHEN** a benchmark runs
- **THEN** enumeration covers only runnable backends' rows
- **AND** no mlx-audio reference row appears as a candidate
