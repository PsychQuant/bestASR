## MODIFIED Requirements

### Requirement: Full-family catalog

The model grid SHALL carry the full-family catalog — the 15-family mlx-audio reference rows untouched — plus live rows for the `fluid-parakeet` backend (parakeet family, sizes as shipped by the pinned FluidAudio release) that enumerate as benchmark candidates. The mlx-audio reference rows carry verified HuggingFace repos with pinned revisions; they become runnable candidates only while a registered external adapter (#51, spec external-engine-protocol) makes the `mlx-audio` backend available — otherwise they stay reference-only.

#### Scenario: Live and reference parakeet rows coexist distinguishably

- **WHEN** the grid is queried for the parakeet family
- **THEN** it returns both the live `fluid-parakeet` row(s) and the reference `mlx-audio` row, distinguishable by backend id

#### Scenario: Reference catalog integrity is preserved

- **WHEN** the grid seeds the store after this change
- **THEN** all 15 mlx-audio reference families remain present with their pinned HF repo/revision metadata, and none enumerate as candidates

### Requirement: Priority tiers gate the default sweep

Grid rows SHALL carry priority 1, 2, or 3. For runnable backends every current row is priority 1 and enumerates by default; for the mlx-audio catalog the tier was historical metadata while reference-only; once an external adapter registers the backend (#51), the same priority gate applies — the default sweep covers its priority-1 rows and `--all-grid` widens to the rest.

#### Scenario: default sweep

- **WHEN** a benchmark runs
- **THEN** enumeration covers only runnable backends' rows
- **AND** no mlx-audio reference row appears as a candidate
