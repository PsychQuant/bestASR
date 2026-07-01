## ADDED Requirements

### Requirement: Rank candidates by measured benchmark data

When the machine-local benchmark cache contains records whose backend is currently available and whose language matches the request, the router SHALL rank those candidates by the active profile weighting over measured error rate and measured RTF and SHALL recommend the highest-ranked candidate, including its quantization. The recommendation SHALL mark its data source as measured.

#### Scenario: Measured data drives the recommendation

- **WHEN** the cache holds matching records for whisperkit large-v3-turbo and whisper.cpp small
- **AND** the profile is `accurate`
- **THEN** the recommendation is the candidate with the better profile-weighted score
- **AND** the recommendation data source is `measured`

##### Example: profile flips the winner on the same measurements

| Candidate                 | CER  | x-realtime | accurate profile picks | fast profile picks |
| ------------------------- | ---- | ---------- | ---------------------- | ------------------ |
| whisperkit large-v3-turbo | 0.05 | 12.0       | ✓                      |                    |
| whisper.cpp small q5      | 0.15 | 20.0       |                        | ✓                  |

#### Scenario: Stale-machine records are ignored

- **WHEN** every cache record was measured on a different chip identifier than the current machine
- **THEN** the router treats the cache as empty and falls back to the cold-start prior

### Requirement: Cold-start prior when no benchmark data exists

When no usable benchmark record exists for the request, the router SHALL fall back to a static prior: select the preferred available backend (whisperkit first, then whisper.cpp), select the most accurate model in the active profile's candidate list (`fast` → tiny/base/small, `balanced` → small/medium, `accurate` → medium/large-v3-turbo/large-v3) whose estimated memory requirement fits unified memory, and mark the recommendation data source as cold-start prior. The reasons SHALL include a suggestion to run the benchmark command for measured, machine-specific recommendations.

#### Scenario: Cold start recommends from the prior and suggests benchmarking

- **WHEN** the benchmark cache is empty and whisperkit is available
- **AND** the profile is `balanced`
- **THEN** the recommendation backend is `whisperkit` with a model from the balanced candidate list
- **AND** the recommendation data source is `cold_start_prior`
- **AND** `reason` contains an entry suggesting to run the benchmark command

## MODIFIED Requirements

### Requirement: Honor explicit backend override with fallback

When the caller specifies an explicit backend, the router SHALL use it if available. If the requested backend is unavailable, the router SHALL fall back to the best available backend (whisperkit first, then whisper.cpp) and SHALL append a warning naming the unavailable backend.

#### Scenario: Requested backend unavailable falls back

- **WHEN** the caller requests `whisper.cpp` but it is not available
- **AND** whisperkit is available
- **THEN** the recommendation backend is `whisperkit`
- **AND** `warnings` contains an entry stating that `whisper.cpp` was requested but unavailable

### Requirement: Downgrade model when memory is insufficient

Within the cold-start prior, when the estimated requirement of the selected model exceeds available unified memory, the router SHALL downgrade along the chain `large-v3 → medium → small → base → tiny` until the model fits, appending a warning and a reason for each downgrade step. Measured-data rankings are not downgraded: a benchmarked candidate has already run on this machine.

#### Scenario: Insufficient unified memory downgrades from large to a smaller model

- **WHEN** the cold-start prior selects `large-v3` but available unified memory is below its estimated requirement
- **THEN** the router selects the first smaller model in the chain that fits
- **AND** `warnings` records that a larger model did not fit

##### Example: downgrade steps by available memory

| Available memory | Start model | Final model | Warnings recorded |
| ---------------- | ----------- | ----------- | ----------------- |
| fits large-v3    | large-v3    | large-v3    | 0                 |
| fits medium only | large-v3    | medium      | 1                 |
| fits small only  | large-v3    | small       | 2                 |

### Requirement: Produce an explainable recommendation

Every recommendation SHALL be an `ASRRecommendation` carrying `backend`, `model`, `quantization`, `profile`, `language`, `data_source` (`measured` or `cold_start_prior`), an optional `measured` summary (metric kind, error rate, and RTF when the data source is measured), a non-empty `reason` list, and a `warnings` list. When the data source is measured, at least one reason SHALL cite the measured figures.

#### Scenario: Measured recommendation cites its numbers

- **WHEN** the router recommends from benchmark data with CER 0.05 and 12x realtime
- **THEN** `data_source` is `measured`
- **AND** `reason` contains an entry citing the measured error rate and speed

#### Scenario: Cold-start recommendation is explainable without measurements

- **WHEN** the router recommends from the cold-start prior
- **THEN** `data_source` is `cold_start_prior` and `measured` is null
- **AND** `reason` contains at least one human-readable entry explaining the backend and model choice

### Requirement: Handle absence of any available backend

When no backend is available, the router SHALL NOT return a runnable recommendation and SHALL surface an error that lists the supported backends (whisperkit, whisper.cpp) and how to install or enable them.

#### Scenario: No backend installed

- **WHEN** neither whisperkit nor whisper.cpp reports availability
- **THEN** the router raises a clear error naming both supported backends and install guidance

## REMOVED Requirements

### Requirement: Select backend by rule-based decision table

**Reason**: The Apple Silicon-only re-platform removes the cross-platform backend-family split (MLX vs CUDA vs CPU) that the decision table encoded; backend choice is now driven by measured benchmark ranking with a whisperkit-first prior.
**Migration**: See ADDED requirements "Rank candidates by measured benchmark data" and "Cold-start prior when no benchmark data exists".

### Requirement: Select model and compute type by profile scoring

**Reason**: Static characteristics-table scoring is replaced by measured benchmark ranking; compute type selection (fp16/int8 per CUDA VRAM) is obsolete on Apple-only targets where quantization variants are benchmarked directly.
**Migration**: Profile candidate lists survive inside the ADDED "Cold-start prior when no benchmark data exists"; measured selection is covered by "Rank candidates by measured benchmark data".
