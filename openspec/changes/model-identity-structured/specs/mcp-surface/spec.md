## ADDED Requirements

### Requirement: Model-listing tools report structured identity

The `list_models` and `list_backends` tools SHALL report a model's family, size and hosting runtime as separate fields, so a client can group one model across its runtimes without parsing a composite string.

As with the CLI, removing the literal `default` from the emitted values lives with the catalog re-key, not here.

#### Scenario: A client can relate one model across runtimes

- **WHEN** an MCP client calls `list_models` and the catalog holds one model hosted by two runtimes
- **THEN** both entries carry the same family and size, and differ in the runtime field, so the client can group them without parsing a composite string

#### Scenario: Incomplete identities are marked for the client

- **WHEN** a listed model's size or quantization is unrecorded
- **THEN** the entry carries `identity_complete: false`, so a client does not treat it as comparable with complete entries

Note: while the catalog still spells the placeholder, only the two rows with no published size report `false`. The quantization axis begins reporting it with the re-key.
