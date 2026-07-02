## ADDED Requirements

### Requirement: Cue-level speaker diarization on demand

When transcription is invoked with diarization enabled, the system SHALL run acoustic speaker diarization over the input audio (FluidAudio CoreML pipeline, models fetched and cached by the vendored SDK on first use) and assign each transcript segment the speaker whose diarized turn has the greatest time overlap with that segment. Speaker labels SHALL be `SPEAKER_1`-based ordinals in order of first appearance; a segment with no overlapping turn SHALL carry no speaker rather than a fabricated one. Diarization failure with diarization explicitly requested SHALL fail the command loudly — never silently degrade to unlabeled output.

#### Scenario: multi-speaker audio gets distinct labels

- **GIVEN** an audio file containing three speakers in sequence with known change points
- **WHEN** transcription runs with diarization enabled
- **THEN** the transcript segments carry at least two distinct `SPEAKER_N` labels and the label changes fall near the known speaker-change boundaries

#### Scenario: single-speaker audio stays single

- **WHEN** a single-speaker clip is transcribed with diarization enabled
- **THEN** every labeled segment carries the same single `SPEAKER_1` label

#### Scenario: diarization off is byte-identical to before

- **WHEN** transcription runs without diarization
- **THEN** every output format is byte-identical to the pre-diarization behavior (no speaker fields, no prefixes)
