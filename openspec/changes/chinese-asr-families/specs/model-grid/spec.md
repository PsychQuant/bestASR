## MODIFIED Requirements

### Requirement: Full-family catalog

The model grid SHALL carry the full-family catalog — the 15-family mlx-audio reference rows untouched — plus live rows for the FluidAudio-backed backends (`fluid-parakeet` parakeet family, `fluid-paraformer` paraformer family, `fluid-sensevoice` sensevoice family, sizes as shipped by the pinned FluidAudio release) that enumerate as benchmark candidates.

#### Scenario: Grid lists both live and reference rows for one family

- **WHEN** the grid is filtered to the parakeet family
- **THEN** it returns both the live `fluid-parakeet` row(s) and the reference `mlx-audio` row, distinguishable by backend id

#### Scenario: Chinese-family live rows enumerate

- **WHEN** the grid is filtered to live-engine backends
- **THEN** the `fluid-paraformer` and `fluid-sensevoice` rows appear alongside the whisper and parakeet rows
