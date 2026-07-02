## ADDED Requirements

### Requirement: Corpus registry keyed by content hash

The corpora table SHALL identify each corpus by the SHA-256 of its audio bytes and record the reference transcript hash, language, duration, and current local paths; registering the same audio again SHALL update paths rather than duplicate the row.

#### Scenario: re-add same audio from a new path

- **GIVEN** a registered corpus whose audio moved on disk
- **WHEN** corpus add runs with the new path
- **THEN** the existing row's paths update and no second row appears

### Requirement: corpus add and list subcommands

The CLI SHALL provide `corpus add <audio> <reference> --language <code> [--name]` performing hashing, duration probing, and registry write, and `corpus list` rendering the registry as a table; these are the v1 path for zh/ja user-supplied material.

#### Scenario: register a Chinese corpus

- **WHEN** `bestasr corpus add talk.wav talk.srt --language zh` runs
- **THEN** the registry gains a zh row with both hashes and the probed duration, and `corpus list` shows it

### Requirement: English standard set is scriptable and verified

A fetch script SHALL download the English standard clips (public-domain JFK clip; OSR Harvard sample), convert to 16 kHz mono where needed, verify pinned SHA-256 digests, and register them via corpus add; binaries SHALL NOT be committed to the repository.

#### Scenario: fetch script end-to-end

- **WHEN** the fetch script runs on a clean machine
- **THEN** both English corpora appear in corpus list with verified hashes
