## MODIFIED Requirements

### Requirement: Cue-level speaker diarization on demand

When transcription is invoked with diarization enabled, the system SHALL run acoustic speaker diarization over the input audio (FluidAudio CoreML pipeline, models fetched and cached by the vendored SDK on first use) and assign each transcript segment the speaker whose diarized turn has the greatest time overlap with that segment. Speaker labels SHALL be `SPEAKER_1`-based ordinals internally; rendered output SHALL display them in the human-readable form `Speaker N` with a `: ` separator before the segment text (SRT, VTT, and txt alike), while JSON carries the internal label unchanged.

#### Scenario: Display form maps the internal ordinal

- **WHEN** a segment is assigned the internal label `SPEAKER_2` and rendered to SRT
- **THEN** its cue text is prefixed `Speaker 2: ` (the internal label remains `SPEAKER_2` in JSON output)
