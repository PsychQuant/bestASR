## MODIFIED Requirements

### Requirement: transcribe command with options

`bestasr transcribe <audio>` SHALL transcribe the input and write the result in the requested format, honoring `--profile`, `--backend`, `--model`, `--language`, `--format`, `--output`, and `--context-dir`. When `--format` is omitted it SHALL default to `txt`; when `--output` is omitted the output path SHALL derive from the input file base name and the format extension; when `--context-dir` is omitted the context directory SHALL resolve per the context-calibration three-layer precedence. The command SHALL honor `--diarize`, enabling cue-level speaker diarization per the diarization capability: SRT and VTT cues gain a `[SPEAKER_N] ` text prefix, JSON segments gain a `speaker` field, and txt switches to `SPEAKER_N: ` prefixed lines; without `--diarize` every format's output is unchanged.

#### Scenario: transcribe writes requested format

- **WHEN** the user runs `bestasr transcribe input.mp3 --format srt`
- **THEN** an SRT file is written for the transcript

#### Scenario: defaults apply when options are omitted

- **WHEN** the user runs `bestasr transcribe input.mp3`
- **THEN** the profile is `balanced`, the format is `txt`, and backend, model, and language are chosen automatically

#### Scenario: explicit context directory feeds the transcription

- **WHEN** the user runs `bestasr transcribe input.mp3 --context-dir ./ctx` and `./ctx` contains context values
- **THEN** the rendered context prompt is injected into that transcription run

#### Scenario: diarized SRT carries speaker prefixes

- **WHEN** `bestasr transcribe meeting.wav --format srt --diarize` runs on multi-speaker audio
- **THEN** the written SRT's cues carry `[SPEAKER_N] ` prefixes with at least two distinct labels across the document
