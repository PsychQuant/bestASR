# diarization Specification

## Purpose

TBD - created by archiving change 'speaker-diarization'. Update Purpose after archive.

## Requirements

### Requirement: Cue-level speaker diarization on demand

When transcription is invoked with diarization enabled, the system SHALL run acoustic speaker diarization over the input audio (FluidAudio CoreML pipeline, models fetched and cached by the vendored SDK on first use) and assign each transcript segment the speaker whose diarized turn has the greatest time overlap with that segment. Speaker labels SHALL be `SPEAKER_1`-based ordinals in order of first appearance internally; rendered output (SRT, VTT, and txt alike) SHALL display them in the human-readable form `Speaker N` followed by a `: ` separator before the segment text, while JSON carries the internal label unchanged. The `SPEAKER_<positive integer>` form is reserved for internal ordinals — an enrolled name of that exact shape would be indistinguishable from an ordinal at render time and is not a supported enrollment name. Diarization failure with diarization explicitly requested SHALL fail the command loudly — never silently degrade to unlabeled output; a run whose assignment yields no speaker for any segment (no turns detected, or none overlapping) SHALL likewise fail loudly rather than emit output indistinguishable from diarization off. When the resolved context directory contains enrollment voice samples (`voices/<name>.<audio-ext>`), the system SHALL compute each sample's dominant speaker embedding and, after diarization, label a turn with the enrolled name verbatim (instead of an ordinal) when that turn's speaker embedding is the closest enrolled voice within the recognition threshold; unmatched speakers SHALL keep `SPEAKER_N` ordinals, and enrolled names SHALL NOT consume ordinal numbers. An enrollment sample that cannot be processed SHALL be skipped with a warning rather than aborting the transcription. Enrollment samples and any embeddings derived from them are sensitive biometric data: tooling SHALL NOT upload, commit, or otherwise transmit them off the local machine.

#### Scenario: multi-speaker audio gets distinct labels

- **GIVEN** an audio file containing two speakers in sequence with a known change point (validated fixture: the same FLEURS sentence recorded by a male and a female speaker, concatenated — definitionally distinct speakers)
- **WHEN** transcription runs with diarization enabled
- **THEN** the transcript segments carry two distinct `SPEAKER_N` labels and the label change falls near the known speaker-change boundary

#### Scenario: single-speaker audio stays single

- **WHEN** a single-speaker clip is transcribed with diarization enabled
- **THEN** every labeled segment carries the same single `SPEAKER_1` label

#### Scenario: an all-unlabeled diarize run fails loudly

- **GIVEN** audio whose diarization yields no overlapping turns for any transcript segment
- **WHEN** transcription runs with diarization enabled
- **THEN** the command fails with a runtime error instead of emitting unlabeled output

#### Scenario: diarization off is byte-identical to before

- **WHEN** transcription runs without diarization
- **THEN** every output format is byte-identical to the pre-diarization behavior (no speaker fields, no prefixes)

#### Scenario: an enrolled voice is labeled by name and strangers stay ordinal

- **GIVEN** a context directory whose `voices/` holds an enrollment sample named `TestVoice.wav` for one of two speakers in the audio
- **WHEN** transcription runs with diarization enabled
- **THEN** that speaker's segments are labeled `TestVoice` verbatim while the other speaker keeps `SPEAKER_1`

#### Scenario: no voices folder means pure diarization

- **GIVEN** a resolved context directory without a `voices/` folder
- **WHEN** transcription runs with diarization enabled
- **THEN** the output is identical to enrollment-free diarization (ordinals only)

#### Scenario: display form maps the internal ordinal

- **WHEN** a segment is assigned the internal label `SPEAKER_2` and rendered to SRT
- **THEN** its cue text is prefixed `Speaker 2: ` (the JSON output for the same transcript still carries `SPEAKER_2`)


<!-- @trace
source: speaker-label-display-format
updated: 2026-07-06
code:
  - Sources/BestASRKit/Output/TranscriptWriter.swift
  - Tests/BestASRKitTests/DiarizationTests.swift
  - scripts/validate-diarization.sh
  - README.md
  - CHANGELOG.md
-->
