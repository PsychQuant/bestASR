## MODIFIED Requirements

### Requirement: Corrupt rows degrade loudly, not fatally

A malformed JSONL line SHALL be skipped with a warning naming the table and line number; loading SHALL continue with the remaining rows. Table rewrites (corpus upsert, model seeding) SHALL preserve unparseable lines verbatim in the rewritten file rather than dropping them — user data is never deleted because the store failed to parse it, and the preserved lines keep surfacing the load warning on every subsequent load.

#### Scenario: one bad line

- **GIVEN** a measurements table with one unparseable line among valid rows
- **WHEN** the store loads
- **THEN** valid rows load, and a warning identifies measurements.jsonl and the offending line number

#### Scenario: rewrite preserves the bad line

- **GIVEN** a corpora table containing one unparseable line among valid rows
- **WHEN** a corpus upsert rewrites the table
- **THEN** the rewritten file still contains the unparseable line byte-identical, and the next load warns about it again

### Requirement: Append-only measurements with latest projection

Measurement rows SHALL be append-only; routing and reporting SHALL consume the projection that keeps, per (model, corpus, machine), the row with the greatest measured_at. Each appended measurement SHALL record the Hugging Face revision pin (`hf_revision`) of its model as seeded in the store at measure time when one exists — pin provenance is a measure-time fact that survives later catalog re-seeding — and rows predating this field SHALL decode with a nil revision.

#### Scenario: re-benchmark supersedes without deleting

- **GIVEN** two measurements for the same (model, corpus, machine) with different measured_at
- **WHEN** routing consumes the projection
- **THEN** only the newer row is considered, and both rows remain in the table

#### Scenario: measurement records the pin it was measured at

- **GIVEN** a seeded model row carrying an hf_revision pin
- **WHEN** a benchmark appends a measurement for that model
- **THEN** the measurement row records that revision, and re-seeding the catalog with a new pin later does not alter it
