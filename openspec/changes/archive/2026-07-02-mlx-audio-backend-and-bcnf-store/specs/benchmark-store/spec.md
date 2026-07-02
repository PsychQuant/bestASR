## ADDED Requirements

### Requirement: BCNF four-table store with JSON records

Benchmark persistence SHALL decompose into four JSONL tables — machines, models (the grid), corpora, and measurements — where every record is one JSON object per line and every non-key attribute depends only on its table's key. OS version and app version SHALL live on measurement rows (time-of-measurement facts), not machine rows.

#### Scenario: functional dependencies converge

- **WHEN** the same machine records measurements across two OS versions
- **THEN** the machines table holds one row and the measurements rows carry their own macos_version values

##### Example: measurement row

`{"model_id":"mlx-audio|moonshine|base|default","corpus_id":"a1b2c3d4e5f6","machine_id":"0f1e2d3c4b5a","measured_at":"2026-07-02T12:00:00Z","metric_kind":"wer","error_rate":0.12,"rtf":0.02,"peak_memory_gb":0.4,"warmup_seconds":3.1,"app_version":"0.3.0","macos_version":"27.0"}`

### Requirement: Append-only measurements with latest projection

Measurement rows SHALL be append-only; routing and reporting SHALL consume the projection that keeps, per (model, corpus, machine), the row with the greatest measured_at.

#### Scenario: re-benchmark supersedes without deleting

- **GIVEN** two measurements for the same key triple
- **WHEN** the latest projection is read
- **THEN** only the newer row is used and the older row remains in the file

### Requirement: One-time legacy migration

On first load, an existing legacy flat cache file SHALL be decomposed into the four tables and renamed with a .bak suffix; migration SHALL be idempotent and the migrated data SHALL reproduce the pre-migration recommendation inputs.

#### Scenario: legacy file present

- **GIVEN** a legacy benchmarks.json with N records
- **WHEN** the store loads
- **THEN** four tables exist, the legacy file is renamed .bak, and a second load does not re-migrate

### Requirement: Corrupt rows degrade loudly, not fatally

A malformed JSONL line SHALL be skipped with a warning naming the table and line number; loading SHALL continue with the remaining rows.

#### Scenario: one bad line

- **GIVEN** a measurements table with one unparseable line among valid rows
- **WHEN** the store loads
- **THEN** valid rows load, and a warning identifies measurements.jsonl and the offending line number
