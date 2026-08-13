## ADDED Requirements

### Requirement: Memory estimates are keyed by the full model identity

A model's estimated memory requirement SHALL be resolved by `ModelID`, not by size name alone. Two families sharing a size name SHALL resolve to their own estimates.

#### Scenario: A shared size name no longer collapses two estimates

- **WHEN** the caller requests the requirement for family `sensevoice` size `small`
- **THEN** the estimate is the one recorded for that family, and it is not widened to the estimate of family `whisper` size `small`

#### Scenario: A conservative maximum is no longer needed

- **WHEN** the catalog holds several families that share a size name
- **THEN** each resolves independently, and no reconciliation between colliding names takes place

### Requirement: A runtime states the quantization it loads

An engine that delegates its quantization choice to a third-party package SHALL pass that choice explicitly rather than relying on the package's default.

#### Scenario: A dependency's default no longer decides silently

- **WHEN** an engine loads a model from a package that offers more than one precision
- **THEN** the engine names the precision it requests, so that a change in the package's default does not change what was measured without changing the recorded identity
