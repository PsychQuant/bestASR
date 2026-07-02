## ADDED Requirements

### Requirement: Full-family catalog

The model grid SHALL enumerate every supported (backend, family, size, quantization) combination as catalog rows carrying languages, estimated memory, optional HF repo id, and a priority tier; the mlx-audio backend SHALL enumerate all 15 STT families.

#### Scenario: grid completeness

- **WHEN** the grid is loaded
- **THEN** it contains rows for all 15 mlx-audio families plus the existing WhisperKit and whisper.cpp models, totalling at least 30 rows

### Requirement: Priority tiers gate the default sweep

Grid rows SHALL carry priority 1 (first-run set), 2 (representative), or 3 (deferred/large); benchmark enumeration SHALL default to priority 1 rows for the mlx-audio backend and widen only on explicit request.

#### Scenario: default sweep

- **WHEN** a benchmark runs without grid-widening flags
- **THEN** only priority-1 mlx-audio rows are enumerated

##### Example: first-run set

| model_id | priority |
|---|---|
| `mlx-audio\|whisper\|large-v3-turbo\|4bit` | 1 |
| `mlx-audio\|parakeet\|0.6b\|default` | 1 |
| `mlx-audio\|qwen3-asr\|small\|4bit` | 1 |
| `mlx-audio\|moonshine\|base\|default` | 1 |

### Requirement: Unmeasured is a join fact, not a marker

"Enumerated but not yet measured" SHALL be expressed purely as a grid row lacking a corresponding measurement row; the grid SHALL carry no measurement-status field.

#### Scenario: fresh grid row

- **GIVEN** a grid row with no measurement for the current machine
- **THEN** ranking treats it as unmeasured (cold-start eligible) without any explicit flag

### Requirement: Unverified repo ids are marked, never guessed

Rows whose HF repo id has not been verified against the hub SHALL carry an explicit unverified marker, and download guidance SHALL never fabricate a repo path for them.

#### Scenario: unverified row guidance

- **WHEN** a transcription is requested for an unverified row
- **THEN** the error directs the user to locate the model on the hub instead of printing a guessed URL
