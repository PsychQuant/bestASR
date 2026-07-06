## MODIFIED Requirements

### Requirement: Rank candidates by measured benchmark data

The router SHALL rank candidates by measured benchmark data across every runnable backend — bundled engines and registered external engines alike — regardless of model family. Before ranking, records SHALL be aggregated per candidate (backend, model, quantization): error rate and realtime factor are the equal-weight means over that candidate's usable records, so a single flattering measurement on a short corpus can never outrank a broadly measured candidate. An aggregated candidate whose mean error rate exceeds 0.5 SHALL be excluded from autonomous ranking (more than half wrong has negative practical value); if exclusion empties the pool the router falls back to the cold-start prior, and an explicitly locked backend bypasses the floor with a quality warning in the reasons. Catalog rows whose backend has neither a bundled engine nor a registered, available external adapter SHALL remain excluded from enumeration (reference-only, unchanged from #20); registering an adapter (#51) is what upgrades those rows to candidates.

#### Scenario: Cross-family candidate wins on merit

- **WHEN** measured records show a fluid-parakeet model outperforming every Whisper variant for the requested language under the active profile
- **THEN** `recommend` returns the fluid-parakeet candidate as the top choice with its measured evidence

#### Scenario: Family with no coverage for the language loses naturally

- **WHEN** the requested language has no (or poor) measured results for fluid-parakeet but strong Whisper results
- **THEN** the router ranks the Whisper candidate first — family diversity never overrides measured evidence

#### Scenario: Unregistered reference rows still never enumerate

- **WHEN** candidates are enumerated on a machine with no external-engine registry entry for mlx-audio
- **THEN** mlx-audio reference rows remain excluded, unchanged from #20

#### Scenario: A registered external backend enumerates its rows

- **WHEN** the registry enables `mlx-audio` with an existing executable
- **THEN** mlx-audio catalog rows enumerate as candidates and rank purely on measured evidence (the cold-start prior still never proposes an unmeasured family)

#### Scenario: A single flattering measurement never outranks the aggregate

- **WHEN** one candidate carries a single 0.0-error record on a short corpus while another carries many records averaging 0.09 on real corpora, and the first candidate's own mean over all its records is worse
- **THEN** ranking uses each candidate's mean, and the broadly measured candidate wins

#### Scenario: A candidate below the quality floor is never autonomously recommended

- **WHEN** a candidate's mean error rate for the requested language is 0.93
- **THEN** it is excluded from autonomous ranking even if it is the fastest
- **AND** a candidate within the floor is recommended instead

#### Scenario: The floor never strands the router

- **WHEN** every measured candidate for the language exceeds the floor
- **THEN** the router falls back to the cold-start prior as if unmeasured

#### Scenario: An explicit backend lock bypasses the floor with a warning

- **WHEN** the user locks a backend whose mean error rate exceeds the floor
- **THEN** the route succeeds on that backend and the reasons carry a quality warning
