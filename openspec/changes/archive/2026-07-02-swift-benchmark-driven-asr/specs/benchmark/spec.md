## ADDED Requirements

### Requirement: Enumerate candidate configurations

The benchmark SHALL enumerate candidate configurations as the cross product of available backends, their supported models, and their supported quantization variants on this machine, skipping backends whose availability probe reports false. The caller SHALL be able to narrow candidates with explicit backend and model filters.

#### Scenario: Only available backends produce candidates

- **WHEN** the benchmark enumerates candidates while whisper.cpp is unavailable
- **THEN** no whisper.cpp candidate appears in the run list
- **AND** a note records that whisper.cpp was skipped as unavailable

#### Scenario: Explicit filters narrow the candidate set

- **WHEN** the caller passes a backend filter naming `whisperkit` and a model filter naming `large-v3-turbo`
- **THEN** only whisperkit large-v3-turbo variants are enumerated

### Requirement: Parse SRT reference into ground truth

The benchmark SHALL parse a SubRip (`.srt`) reference file into an ordered list of cues (index, start, end, text) and derive the ground-truth reference text by concatenating cue texts in order. A missing or unparseable reference file SHALL produce a clear error and a usage-error exit, before any transcription starts.

#### Scenario: Valid SRT yields reference text

- **WHEN** the reference file contains two cues with texts "hello" and "world"
- **THEN** parsing yields two cues in order
- **AND** the reference text is the ordered concatenation of "hello" and "world"

#### Scenario: Malformed SRT is rejected before transcription

- **WHEN** the reference file lacks any valid `HH:MM:SS,mmm --> HH:MM:SS,mmm` timecode line
- **THEN** a clear parse error is raised naming the file
- **AND** no candidate transcription is started

### Requirement: Compute accuracy metric selected by language

The benchmark SHALL compute an edit-distance-based error rate between the normalized hypothesis and the normalized reference: character error rate (CER) for languages written without word spacing (including `zh`, `ja`, `ko`), and word error rate (WER) with whitespace tokenization otherwise. The report SHALL name which metric kind was used. Normalization applied to both sides SHALL include Unicode NFKC, punctuation removal, fullwidth-to-halfwidth folding, lowercasing, and whitespace collapsing.

#### Scenario: Chinese audio uses CER

- **WHEN** the benchmark language is `zh`
- **THEN** the accuracy metric kind is `cer`

#### Scenario: English audio uses WER

- **WHEN** the benchmark language is `en`
- **THEN** the accuracy metric kind is `wer`

##### Example: CER on a five-character reference

- **GIVEN** normalized reference "今天天氣好" and normalized hypothesis "今天天很好"
- **WHEN** CER is computed
- **THEN** the edit distance is 1 substitution over 5 reference characters and CER = 0.2

##### Example: WER on a four-word reference

- **GIVEN** normalized reference "the cat sat down" and normalized hypothesis "the cat sat"
- **WHEN** WER is computed
- **THEN** the edit distance is 1 deletion over 4 reference words and WER = 0.25

### Requirement: Measure speed and memory per candidate

For each candidate the benchmark SHALL measure the real-time factor (RTF) as wall-clock transcription seconds divided by audio duration seconds, timed after a warm-up model load so that model download and first-load time are excluded from RTF and reported separately. The benchmark SHALL record an approximate peak memory figure for the transcription and state the measurement method in the report.

#### Scenario: RTF excludes model download time

- **WHEN** a candidate downloads its model before transcribing a 60-second clip in 5 wall-clock seconds of transcription time
- **THEN** the recorded RTF is 5/60
- **AND** the download time is reported separately from RTF

### Requirement: Rank candidates and report results

The benchmark SHALL rank successfully measured candidates by the active profile weighting over accuracy and speed and SHALL print a report table containing, per candidate: backend, model, quantization, error rate with metric kind, times-realtime, peak memory, and rank. A machine-readable JSON output mode SHALL be available.

#### Scenario: Report contains ranked rows

- **WHEN** three candidates complete measurement
- **THEN** the report lists three rows each carrying backend, model, quantization, error rate, times-realtime, peak memory, and a distinct rank

##### Example: accuracy-first ranking under the accurate profile

| Candidate                     | CER  | x-realtime | Rank (accurate profile) |
| ----------------------------- | ---- | ---------- | ----------------------- |
| whisperkit large-v3-turbo     | 0.05 | 12.0       | 1                       |
| whisper.cpp large-v3 q5       | 0.06 | 6.0        | 2                       |
| whisper.cpp small q5          | 0.15 | 20.0       | 3                       |

### Requirement: Persist benchmark results to a machine-local cache

The benchmark SHALL persist each measured result to a machine-local cache keyed by backend, model, quantization, and language, with each record carrying error rate, metric kind, RTF, peak memory, audio duration, measurement timestamp, chip identifier, macOS version, and app version. A new measurement for an existing key SHALL replace the prior record. The cache SHALL be consumable by the routing capability.

#### Scenario: Re-running benchmark replaces the record for the same key

- **WHEN** the same backend, model, quantization, and language combination is benchmarked twice
- **THEN** the cache holds one record for that key carrying the newer measurement timestamp

### Requirement: Warn-continue on per-candidate failure

When a single candidate fails (download error, transcription error, or resource exhaustion), the benchmark SHALL record the failure with its reason, emit a warning, and continue with the remaining candidates. The benchmark SHALL exit non-zero only when every candidate fails.

#### Scenario: One failing candidate does not abort the run

- **WHEN** one of three candidates fails to transcribe
- **THEN** the other two candidates are still measured and ranked
- **AND** the failed candidate is listed with its failure reason

#### Scenario: All candidates failing is a runtime failure

- **WHEN** every enumerated candidate fails
- **THEN** the benchmark exits with a non-zero status and a clear message
