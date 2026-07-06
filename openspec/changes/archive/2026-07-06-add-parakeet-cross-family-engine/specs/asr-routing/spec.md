## MODIFIED Requirements

### Requirement: Rank candidates by measured benchmark data

The router SHALL rank candidates by measured benchmark data across every backend that has a bundled engine — including `fluid-parakeet` — regardless of model family. Reference-only catalog rows (backends without a bundled engine) SHALL remain excluded from enumeration.

#### Scenario: Cross-family candidate wins on merit

- **WHEN** measured records show a fluid-parakeet model outperforming every Whisper variant for the requested language under the active profile
- **THEN** `recommend` returns the fluid-parakeet candidate as the top choice with its measured evidence

#### Scenario: Family with no coverage for the language loses naturally

- **WHEN** the requested language has no (or poor) measured results for fluid-parakeet but strong Whisper results
- **THEN** the router ranks the Whisper candidate first — family diversity never overrides measured evidence

#### Scenario: Reference rows still never enumerate

- **WHEN** candidates are enumerated
- **THEN** mlx-audio reference rows remain excluded (no bundled engine), unchanged from #20
