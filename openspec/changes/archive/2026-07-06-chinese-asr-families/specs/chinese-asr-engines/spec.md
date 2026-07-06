## ADDED Requirements

### Requirement: ParaformerEngine conforms to the Engine seam

The system SHALL provide a `fluid-paraformer` backend backed by FluidAudio's ParaformerManager (Chinese large model), conforming to the same Engine seam as the other bundled engines: an injectable pipeline protocol for tests, a create-once pipeline store keyed by model, and typed `TranscriptionError` mapping that names the backend on failure.

#### Scenario: Paraformer transcribes through the seam

- **WHEN** `transcribe` runs with `--backend fluid-paraformer` on Chinese audio
- **THEN** the transcript text comes from the Paraformer pipeline and the result carries the `fluid-paraformer` backend id

#### Scenario: Pipeline failure surfaces as a typed error

- **WHEN** the pipeline factory throws (e.g. model download failure)
- **THEN** the engine surfaces a `TranscriptionError` naming `fluid-paraformer` and the underlying reason

### Requirement: SenseVoiceEngine conforms to the Engine seam

The system SHALL provide a `fluid-sensevoice` backend backed by FluidAudio's SenseVoiceManager, conforming to the same Engine seam. The pipeline SHALL use SenseVoice's automatic language detection (the upstream default): FluidAudio 0.15.4 does not export the per-language embed-index table, and a wrong guessed index would silently degrade quality — an explicit hint mapping waits for upstream constants. A language request therefore never fails transcription regardless of value.

#### Scenario: Any language request transcribes via auto-detection

- **WHEN** `transcribe --backend fluid-sensevoice --language zh` (or any other code) runs
- **THEN** the SenseVoice pipeline transcribes with automatic language detection and the result carries the `fluid-sensevoice` backend id

### Requirement: Text-only families yield a single full-text segment

Both Chinese engines receive plain text from their pipelines (no confidence, no token timings). The raw transcription SHALL be a single segment spanning the probed audio duration with the full text and a nil confidence — the engine SHALL NOT fabricate sub-segment timings. Timed-cue output formats consequently carry one cue for the whole file; benchmark error rates, which compare full text, are unaffected.

#### Scenario: No fabricated timings

- **WHEN** a Chinese engine transcribes a 30-second file
- **THEN** the raw result has exactly one segment with start 0 and end at the probed duration
- **AND** its confidence is nil
