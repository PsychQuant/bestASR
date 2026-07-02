## ADDED Requirements

### Requirement: zh/ja standard set is scriptable and verified

The fetch script SHALL download, verify, and register standard Mandarin and Japanese clips built from the FLEURS dataset (CC-BY-4.0; three distinct dev-split utterances per language, concatenated to one 16 kHz mono clip with an embedded verbatim SRT reference). The supply chain SHALL be pinned end to end: the dataset revision is content-addressed, the raw tar digest is verified BEFORE any parser touches the bytes, and the converted concatenated artifact digest is verified before registration; binaries SHALL NOT be committed to the repository.

#### Scenario: one command registers zh and ja corpora

- **WHEN** the fetch script runs on a machine with network access
- **THEN** `corpus list` shows a zh corpus and a ja corpus with their durations, both registered through `corpus add`

#### Scenario: tampered download refuses to parse

- **GIVEN** a FLEURS tar whose bytes do not match the pinned digest
- **WHEN** the fetch script verifies the raw download
- **THEN** it refuses to extract or convert, that language's corpus is not registered, and the remaining corpora still register (per-corpus isolation)
