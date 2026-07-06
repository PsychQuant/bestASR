## MODIFIED Requirements

### Requirement: Full-family catalog

The model grid SHALL carry the full-family catalog — the 15-family mlx-audio reference rows untouched — plus live rows for the FluidAudio-backed backends (`fluid-parakeet` parakeet family, `fluid-paraformer` paraformer family, `fluid-sensevoice` sensevoice family, sizes as shipped by the pinned FluidAudio release). Priority-1 live rows enumerate as default benchmark candidates; a live row may sit at a lower tier when its family is wired but not yet usable (e.g. an upstream decode bug), keeping it out of the default sweep.

#### Scenario: Live and reference parakeet rows coexist distinguishably

- **WHEN** the grid is queried for the parakeet family
- **THEN** it returns both the live `fluid-parakeet` row(s) and the reference `mlx-audio` row, distinguishable by backend id

#### Scenario: Reference catalog integrity is preserved

- **WHEN** the grid seeds the store after this change
- **THEN** all 15 mlx-audio reference families remain present with their pinned HF repo/revision metadata, and none enumerate as candidates

#### Scenario: Chinese-family live rows are listed

- **WHEN** the grid is filtered to live-engine backends with no priority ceiling
- **THEN** the `fluid-paraformer` and `fluid-sensevoice` rows appear alongside the whisper and parakeet rows

### Requirement: Priority tiers gate the default sweep

Grid rows SHALL carry priority 1, 2, or 3. For runnable backends, rows default to priority 1 and enumerate by default — but a wired-yet-unusable family MAY be shelved at priority 2 so the default sweep never pays its download (#50: paraformer, upstream decode bug); for the mlx-audio reference catalog the tier is retained as historical metadata (the original first-run/representative/deferred selection) and has no enumeration effect.

#### Scenario: default sweep

- **WHEN** a benchmark runs
- **THEN** enumeration covers only runnable backends' rows
- **AND** no mlx-audio reference row appears as a candidate
