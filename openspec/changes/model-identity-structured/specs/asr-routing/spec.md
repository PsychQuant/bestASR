## ADDED Requirements

### Requirement: Candidate ranking covers every family, not only the whisper ladder

The accuracy ordering used by the cold-start prior SHALL be defined for every family present in the catalog. A model SHALL NOT be ordered last merely because its family is absent from a whisper-shaped list.

#### Scenario: A non-whisper family receives a defined rank

- **WHEN** the router orders candidates and the catalog contains families such as `parakeet`, `paraformer` or `sensevoice`
- **THEN** each receives a defined ordinal, and none is treated as unranked because its family is not a whisper size

#### Scenario: Downgrade succession is defined per family

- **WHEN** memory is insufficient and the router seeks a smaller model
- **THEN** the successor is sought within the same family, and a family without a defined successor terminates the chain rather than falling through to another family's ladder

### Requirement: Candidates with an incomplete identity are excluded and named

The router SHALL exclude any candidate whose identity is incomplete, and SHALL state the exclusion in its notes.

#### Scenario: An unknown quantization removes a candidate loudly

- **WHEN** a catalog row's quantization is unknown
- **THEN** the row is not offered as a candidate, and the recommendation's notes name the row and the reason
