## ADDED Requirements

### Requirement: Enrollment voices folder is reserved, local-only, and outside document parsing

The resolved context directory MAY contain a `voices/` subfolder holding speaker-enrollment audio samples named `<label>.<audio-ext>` (wav, m4a, mp3); the filename stem is the label used verbatim by the diarization capability for matching speakers. Files under `voices/` are NOT context documents: they SHALL NOT be parsed as terms, SHALL NOT appear in the unsupported-format ignored list, and SHALL NOT influence the rendered prompt. Enrollment samples and any embeddings derived from them are sensitive biometric data: tooling (including the context-ingest skill) SHALL NOT upload, commit, or otherwise transmit them off the local machine. Explain output SHALL disclose how many enrollment voices were found when diarization uses them.

#### Scenario: voices are consumed by diarization, not by the prompt

- **GIVEN** a resolved context directory containing `voices/Alice.wav` and `context.json`
- **WHEN** transcription runs with diarization enabled
- **THEN** the prompt renders from `context.json` unaffected by the voice file, and segments matching the enrolled voice are labeled `Alice`

#### Scenario: voices folder never leaves the machine

- **WHEN** any bestASR tooling (CLI or plugin skills) processes a context directory containing `voices/`
- **THEN** no voice sample or derived embedding is uploaded, committed, or transmitted anywhere
