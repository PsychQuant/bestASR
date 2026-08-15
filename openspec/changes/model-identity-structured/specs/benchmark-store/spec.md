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

### Requirement: Records carry whether they can attest which artifact produced them

A projected measurement SHALL expose, separately from identity completeness, whether it can say WHICH artifact produced it. That answer SHALL be derived from the record's own facts — a concrete quantization in its stored key, a revision pin recorded on the measurement itself, or a runtime with no quantization dimension — and SHALL NOT be derived from the catalog's present contents.

A record that cannot attest its artifact SHALL still rank. The recommendation SHALL name what it cannot vouch for.

#### Scenario: The catalog's present value does not attest a past measurement

- **WHEN** a stored key records its quantization as the removed placeholder, and the catalog row for that model states a concrete value today
- **THEN** the record is not attested, because the catalog describes what the runtime loads now and not what the measurement ran on

#### Scenario: A recorded revision pin attests even without a named quantization

- **WHEN** a measurement carries the revision it was seeded with
- **THEN** it is attested, because the artifact is frozen by that pin whether or not its quantization was ever labelled

#### Scenario: Unattested records rank and are named

- **WHEN** the router ranks candidates and some cannot attest their artifact
- **THEN** they are ranked rather than dropped, and the recommendation states which candidates cannot promise a like-for-like comparison

#### Scenario: A merged candidate attests only if every run did

- **WHEN** a candidate's measurements collapse into one record and any component could not attest its artifact
- **THEN** the merged record cannot attest either

#### Scenario: Incomplete records remain readable

- **WHEN** a caller lists stored measurements
- **THEN** records marked incomplete are still returned, so that history remains auditable
