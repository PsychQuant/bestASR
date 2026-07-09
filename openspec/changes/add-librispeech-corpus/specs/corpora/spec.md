## ADDED Requirements

### Requirement: LibriSpeech English standard-benchmark set is scriptable and verified

The fetch script SHALL download the LibriSpeech `test-clean` and `dev-clean`
splits from OpenSLR (openslr.org/12), which are CC BY 4.0 and account-free, verify
the pinned SHA-256 digest of each source tarball before extracting, decode a
deterministic sample of utterances from FLAC to 16 kHz mono PCM16, concatenate
them into medium-length corpora each carrying an embedded verbatim SRT reference,
verify the pinned digest of each converted concatenated artifact before
registration, and register them via `corpus add --language en`. Binaries SHALL NOT
be committed to the repository (audio lands under `~/.bestasr/corpora`). The set
SHALL provide approximately 20–30 utterances grouped into 3–5 medium-length
corpora (each a handful of concatenated utterances) so per-corpus metrics can be
averaged and their variance observed. The supply chain SHALL be pinned end to end:
the source tarball digest is verified before any decode touches the bytes, and
each converted concatenated artifact digest is verified before registration.

#### Scenario: fetch script registers the LibriSpeech corpora

- **WHEN** the fetch script's LibriSpeech step runs on a machine with network access
- **THEN** `corpus list` shows 3–5 LibriSpeech English corpora (language en) with their durations, all registered through `corpus add`, each with a verified hash

#### Scenario: tampered LibriSpeech download refuses to register

- **GIVEN** a LibriSpeech source tarball whose bytes do not match the pinned digest
- **WHEN** the fetch script verifies the raw download
- **THEN** it refuses to extract, decode, or register anything from that download (fail-closed), and the other languages' corpora still register (per-language isolation)

#### Scenario: converted-artifact digest guards conversion drift

- **GIVEN** a converted concatenated LibriSpeech artifact whose digest does not match the pinned value (e.g. ffmpeg/decoder drift)
- **WHEN** the fetch script verifies the converted artifact
- **THEN** it registers nothing for that group and reports the mismatch, rather than registering a silently-different corpus
