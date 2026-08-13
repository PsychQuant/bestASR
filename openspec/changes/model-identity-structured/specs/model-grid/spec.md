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

### Requirement: Size is normalised to the pinned upstream artifact

Where a catalog row pins an upstream repository, its `size` SHALL name the model version that the pinned artifact declares. A row SHALL NOT carry an abbreviated size that differs from the version its pin resolves to.

#### Scenario: Abbreviated size is rejected in favour of the pinned version

- **WHEN** a row pins `mlx-community/parakeet-tdt-0.6b-v3` and declares size `0.6b`
- **THEN** the row is invalid, because the pinned artifact declares version `0.6b-v3`

#### Scenario: Rows without a pin keep their declared size

- **WHEN** a row has no upstream repository because the runtime fetches its own weights
- **THEN** the declared size stands, and the spec records that the version is managed by the runtime

### Requirement: Quantization is a closed enumeration with no placeholder

A catalog row's quantization SHALL be one of: not applicable, a named value, deferred to a stated decider, or unknown. The literal string `default` SHALL NOT appear as a quantization or a size in any row.

#### Scenario: A runtime without a quantization dimension states so

- **WHEN** a row describes an OS-bundled model that offers no quantization choice
- **THEN** its quantization is `not applicable`, distinguishable from a value that is merely unrecorded

#### Scenario: A value chosen by a dependency states its decider

- **WHEN** a row's quantization is selected by a third-party package rather than by this project
- **THEN** the row records that the value is deferred and names the dependency as the decider, so that a dependency version change is recognisable as a possible change of quantization

#### Scenario: An unknown quantization excludes the row from comparison

- **WHEN** a row's quantization is unknown
- **THEN** the row remains listable for reference, and it SHALL be excluded from benchmark candidate enumeration with a named note stating why
