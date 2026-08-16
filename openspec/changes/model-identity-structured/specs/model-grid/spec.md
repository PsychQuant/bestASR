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

### Requirement: Quantization is a closed enumeration with no placeholder

A catalog row's quantization SHALL be one of: not applicable, a named value, deferred to a stated decider, or unknown — a closed set, not a free string. The literal string `default` SHALL NOT appear as a quantization in any row.

Rotating a row's stored key does not orphan the measurements taken under the old one: a stored key is mapped onto today's identity when it is read, so the file is never rewritten and both spellings resolve to one candidate.


### Requirement: A stored key resolves to the model the catalog now holds

A `model_id` written by an earlier version SHALL resolve to the identity the catalog uses today, without rewriting the stored record. A measurement taken before a row stated its quantization SHALL rank as the same candidate as one taken after.

#### Scenario: A rotated key and its replacement are one candidate

- **WHEN** the store holds measurements keyed `whisperkit|whisper|large-v3-turbo|default` and the catalog now spells that row's quantization `deferred:runtime`
- **THEN** both resolve to one identity and one quantization, and the candidate appears once in the ranking pool

#### Scenario: A renamed size resolves to the name its pin declares

- **WHEN** the store holds measurements keyed `mlx-audio|parakeet|0.6b|default` and the catalog names that row `0.6b-v3`, the version its pin resolves to
- **THEN** the stored key resolves to `parakeet 0.6b-v3`, the same identity the fluid-parakeet row carries

### Requirement: A model's address does not depend on the runtime hosting it

A model SHALL be addressed identically under every runtime. Changing which runtime hosts a model SHALL NOT change the string that names it.

#### Scenario: One address names one model everywhere

- **WHEN** the catalog holds `whisper base` under whisperkit and `moonshine base` under mlx-audio
- **THEN** they are addressed `whisper/base` and `moonshine/base`, and no string names both
