## MODIFIED Requirements

### Requirement: English standard set is scriptable and verified

A fetch script SHALL download the English standard clips (public-domain JFK clip; OSR Harvard samples), convert to 16 kHz mono where needed, verify pinned SHA-256 digests, and register them via corpus add; binaries SHALL NOT be committed to the repository. The English set SHALL provide approximately 20-30 utterances total, grouped into 3-5 medium-length corpora (each a handful of concatenated utterances) rather than a single clip, so per-corpus metrics can be averaged and their variance observed.

#### Scenario: fetch script end-to-end

- **WHEN** the fetch script runs on a clean machine
- **THEN** the English corpora (3-5 of them, ~20-30 utterances total) appear in corpus list with verified hashes

### Requirement: zh/ja standard set is scriptable and verified

The fetch script SHALL download, verify, and register standard **Traditional Chinese (Taiwanese Mandarin)** and Japanese clips. The Traditional Chinese material SHALL come from Mozilla Common Voice zh-TW (CC-0); the Japanese material from the FLEURS dataset (CC-BY-4.0). Simplified Chinese SHALL NOT be part of the standard set — bestASR's "Chinese" benchmark corpus is Traditional Chinese only, and the previously-registered Simplified FLEURS `cmn_hans_cn` corpus SHALL be removed. Each language SHALL provide approximately 20-30 utterances, grouped into 3-5 medium-length corpora (each 5-8 concatenated utterances at 16 kHz mono with an embedded verbatim SRT reference) rather than a single concatenated clip. The supply chain SHALL be pinned end to end: for Common Voice, the source dataset revision is content-addressed (pinned mirror revision), the audio shard digest is verified before any parser touches the bytes, and each selected clip's filename and SHA-256 are pinned; for FLEURS, the dataset revision is content-addressed and the raw tar digest is verified before any parser touches the bytes; every converted concatenated artifact digest is verified before registration; binaries SHALL NOT be committed to the repository. The `zh` language code is retained (it selects the CER metric, which applies to Traditional and Simplified alike) but denotes Traditional Chinese throughout.

#### Scenario: one command registers Traditional Chinese and ja corpora

- **WHEN** the fetch script runs on a machine with network access
- **THEN** `corpus list` shows 3-5 Traditional-Chinese (Common Voice zh-TW) corpora and 3-5 Japanese corpora with their durations, all registered through `corpus add`, and no Simplified Chinese corpus is present

#### Scenario: tampered download refuses to parse

- **GIVEN** a download (Common Voice clip or FLEURS tar) whose bytes do not match the pinned digest
- **WHEN** the fetch script verifies the raw download
- **THEN** it refuses to extract, convert, or register anything from that download — the affected language registers nothing (fail-closed) — and the other languages' corpora still register (per-language isolation)
