## ADDED Requirements

### Requirement: Model identity is a structured value, not a formatted string

A model SHALL be identified by a `ModelID` value carrying `family` and `size`, paired with the runtime that hosts it. The catalog SHALL NOT accept a model address whose grammar depends on which runtime hosts the row.

#### Scenario: The same model under two runtimes is one identity

- **WHEN** the catalog holds a row for family `parakeet` size `0.6b-v3` under the `fluid-parakeet` runtime and another under the `mlx-audio` runtime
- **THEN** both rows resolve to the same `ModelID`, and a caller can determine that they differ only by runtime

#### Scenario: Two families sharing a size name are distinct identities

- **WHEN** the catalog holds family `whisper` size `small` and family `sensevoice` size `small`
- **THEN** the two rows resolve to different `ModelID` values, and a lookup for one SHALL NOT return the other

#### Scenario: Lookup is unambiguous for every runtime

- **WHEN** a caller resolves a catalog row by `ModelID` and runtime
- **THEN** at most one row matches, and no runtime requires a different addressing grammar from any other

### Requirement: Quantization is a closed enumeration

A catalog row's quantization SHALL be one of: not applicable, a named value, deferred to a stated decider, or unknown — a closed set, not a free string.

Assigning each row its true value, and thereby removing the literal `default` from every identity, is NOT part of this change: doing so rotates 19 of the 37 stored `model_id` keys while 344 of 383 stored measurements still reference the old ones. That requirement travels with the record re-encoding.

