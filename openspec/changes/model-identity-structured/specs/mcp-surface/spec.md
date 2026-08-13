## ADDED Requirements

### Requirement: Model-listing tools report structured identity

The `list_models` and `list_backends` tools SHALL report a model's family, size and hosting runtime as separate fields. Neither tool SHALL emit the literal string `default` as a quantization or a size.

#### Scenario: A client can relate one model across runtimes

- **WHEN** an MCP client calls `list_models` and the catalog holds one model hosted by two runtimes
- **THEN** both entries carry the same family and size, and differ in the runtime field, so the client can group them without parsing a composite string

#### Scenario: Incomplete identities are marked for the client

- **WHEN** a listed model's quantization is unknown
- **THEN** the entry states that its identity is incomplete, so a client does not treat it as comparable with complete entries
