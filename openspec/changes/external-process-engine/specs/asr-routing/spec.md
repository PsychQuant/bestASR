## MODIFIED Requirements

### Requirement: Rank candidates by measured benchmark data

The router SHALL rank candidates by measured benchmark data across every runnable backend — bundled engines and registered external engines alike — regardless of model family. Catalog rows whose backend has neither a bundled engine nor a registered, available external adapter SHALL remain excluded from enumeration (reference-only, unchanged from #20); registering an adapter (#51) is what upgrades those rows to candidates.

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
