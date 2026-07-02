## MODIFIED Requirements

### Requirement: transcribe command with options

`bestasr transcribe <audio>` SHALL transcribe the input through the routed backend and write the transcript in the selected format (`txt` default, `json`, `srt`, `vtt`) to standard output or `--output <path>`. The command SHALL honor `--model`, `--language`, `--context-dir` (decode-time term biasing per the context-calibration capability), and `--explain`. The command SHALL honor `--diarize`, enabling cue-level speaker diarization per the diarization capability: SRT and VTT cues gain a `[SPEAKER_N] ` text prefix, JSON segments gain a `speaker` field, and txt lines gain a `SPEAKER_N: ` prefix; without `--diarize` every format's output is unchanged. A missing audio file SHALL exit with a usage error before any model work.

#### Scenario: formats render

- **WHEN** `bestasr transcribe talk.wav --format srt` runs
- **THEN** standard output is a valid SubRip document whose cue text concatenation equals the transcript text

#### Scenario: diarized SRT carries speaker prefixes

- **WHEN** `bestasr transcribe meeting.wav --format srt --diarize` runs on multi-speaker audio
- **THEN** cues carry `[SPEAKER_N] ` prefixes with at least two distinct labels across the document
