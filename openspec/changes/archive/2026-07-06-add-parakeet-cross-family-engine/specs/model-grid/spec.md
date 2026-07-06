## MODIFIED Requirements

### Requirement: Full-family catalog

The model grid SHALL carry the full-family catalog — the 15-family mlx-audio reference rows untouched — plus live rows for the `fluid-parakeet` backend (parakeet family, sizes as shipped by the pinned FluidAudio release) that enumerate as benchmark candidates.

#### Scenario: Live and reference parakeet rows coexist distinguishably

- **WHEN** the grid is queried for the parakeet family
- **THEN** it returns both the live `fluid-parakeet` row(s) and the reference `mlx-audio` row, distinguishable by backend id

#### Scenario: Reference catalog integrity is preserved

- **WHEN** the grid seeds the store after this change
- **THEN** all 15 mlx-audio reference families remain present with their pinned HF repo/revision metadata, and none enumerate as candidates
