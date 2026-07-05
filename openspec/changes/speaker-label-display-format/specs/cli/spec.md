## MODIFIED Requirements

### Requirement: transcribe command with options

`bestasr transcribe <audio>` SHALL transcribe the input and write the result in the requested format, honoring `--profile`, `--backend`, `--model`, `--language`, `--format`, `--output`, `--context-dir`, and `--diarize`. When `--format` is omitted it SHALL default to `txt`; when `--output` is omitted the output path SHALL derive from the input file base name and the format extension; when `--context-dir` is omitted the context directory SHALL resolve per the context-calibration three-layer precedence. The command SHALL honor `--diarize`, enabling cue-level speaker diarization per the diarization capability: SRT and VTT cues gain a `Speaker N: ` text prefix (human-readable display form of the internal `SPEAKER_N` ordinal; enrolled real names render as `Name: `), JSON segments gain a `speaker` field carrying the internal label, and txt switches to the same `Speaker N: ` prefixed lines; without `--diarize` every format's output is unchanged.

#### Scenario: Diarized SRT cues carry the human-readable colon prefix

- **WHEN** `bestasr transcribe talk.wav --diarize --format srt` runs and diarization assigns the first segment to `SPEAKER_1`
- **THEN** the cue text reads `Speaker 1: <text>` (no brackets, title-case display label)

#### Scenario: Enrolled speaker names keep the colon convention

- **WHEN** a segment's speaker resolves to an enrolled name (e.g. `Alice`)
- **THEN** the cue text reads `Alice: <text>`
