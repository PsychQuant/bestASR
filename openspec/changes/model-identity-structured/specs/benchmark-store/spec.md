## ADDED Requirements

### Requirement: The persisted model key is unchanged by the identity refactor

The store's `model_id` SHALL remain the four-segment string `runtime|family|size|quantization`. Introducing a structured in-memory identity SHALL NOT alter the serialised form of any existing record.

#### Scenario: Existing records round-trip byte-for-byte

- **WHEN** a model record written before this change is read by the new code and re-serialised
- **THEN** its `model_id` string is identical to the string on disk, and no migration is required to read it

#### Scenario: Projection no longer discards the family segment

- **WHEN** a stored `model_id` is projected into an in-memory record
- **THEN** all four segments survive the projection, and no runtime receives special-case handling that drops the family

### Requirement: Records carry whether their identity is complete

A projected measurement SHALL expose whether the identity it references is complete. A record whose quantization is unknown SHALL be marked incomplete.

#### Scenario: Incomplete identities are excluded from ranking

- **WHEN** the router ranks candidates from measured data
- **THEN** records marked incomplete are excluded from the ranking, and their exclusion is stated rather than silent

#### Scenario: Incomplete records remain readable

- **WHEN** a caller lists stored measurements
- **THEN** records marked incomplete are still returned, so that history remains auditable
