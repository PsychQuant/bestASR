## ADDED Requirements

### Requirement: Select backend by rule-based decision table

The router SHALL select a backend by applying an ordered decision table against `SystemInfo`, choosing the first matching rule whose backend is available. The default order SHALL be: Apple Silicon with MLX available selects `mlx-whisper`; an NVIDIA CUDA GPU selects `faster-whisper`; otherwise a CPU-only host selects `whisper.cpp`.

#### Scenario: Apple Silicon selects mlx-whisper

- **WHEN** `SystemInfo` reports Apple Silicon with `has_mlx` true and mlx-whisper is available
- **THEN** the recommendation backend is `mlx-whisper`
- **AND** `reason` contains an entry stating Apple Silicon and MLX availability

#### Scenario: CUDA host selects faster-whisper

- **WHEN** `SystemInfo` reports `has_cuda` true and faster-whisper is available
- **THEN** the recommendation backend is `faster-whisper`

#### Scenario: CPU-only host selects whisper.cpp

- **WHEN** `SystemInfo` reports no CUDA, no MLX, and whisper.cpp is available
- **THEN** the recommendation backend is `whisper.cpp`

### Requirement: Honor explicit backend override with fallback

When the caller specifies an explicit backend, the router SHALL use it if available. If the requested backend is unavailable, the router SHALL fall back to the best available backend per the decision table and SHALL append a warning naming the unavailable backend.

#### Scenario: Requested backend unavailable falls back

- **WHEN** the caller requests `faster-whisper` but it is not available
- **AND** the host is CPU-only with whisper.cpp available
- **THEN** the recommendation backend is `whisper.cpp`
- **AND** `warnings` contains an entry stating that `faster-whisper` was requested but unavailable

### Requirement: Select model and compute type by profile scoring

The router SHALL select the model from the active profile's candidate model list (`fast` → tiny/base/small, `balanced` → small/medium, `accurate` → medium/large-v3-turbo/large-v3), choosing the most accurate candidate whose estimated memory requirement fits available memory. The candidate lists encode each profile's speed/accuracy trade-off. The profile SHALL default to `balanced` when unspecified. The compute type SHALL be chosen per backend and available memory: `fp16` for MLX; `fp16`, `int8_float16`, or `int8` for CUDA depending on VRAM; and `int8` for CPU whisper.cpp.

#### Scenario: Accurate profile prefers a larger model when memory allows

- **WHEN** the profile is `accurate` and available memory fits `large-v3`
- **THEN** the recommended model is a large-tier model

##### Example: profile changes model selection at equal feasibility

| Profile  | Fits up to | Recommended model |
| -------- | ---------- | ----------------- |
| fast     | large-v3   | small             |
| balanced | large-v3   | medium            |
| accurate | large-v3   | large-v3          |

### Requirement: Downgrade model when memory is insufficient

When the estimated requirement of the selected model exceeds available memory, the router SHALL downgrade along the chain `large-v3 → medium → small → base → tiny` until the model fits, appending a warning and a reason for each downgrade step.

#### Scenario: Insufficient VRAM downgrades from large to a smaller model

- **WHEN** the selected model is `large-v3` but available VRAM is below its estimated requirement
- **THEN** the router selects the first smaller model in the chain that fits
- **AND** `warnings` records that a larger model did not fit

##### Example: downgrade steps by available memory

| Available memory | Start model | Final model | Warnings recorded |
| ---------------- | ----------- | ----------- | ----------------- |
| fits large-v3    | large-v3    | large-v3    | 0                 |
| fits medium only | large-v3    | medium      | 1                 |
| fits small only  | large-v3    | small       | 2                 |

### Requirement: Produce an explainable recommendation

Every recommendation SHALL be an `ASRRecommendation` carrying `backend`, `model`, `compute_type`, `profile`, `language`, `estimated_speed`, `estimated_accuracy`, a non-empty `reason` list, and a `warnings` list.

#### Scenario: Recommendation includes reasons

- **WHEN** the router produces any recommendation
- **THEN** `reason` contains at least one human-readable entry explaining the backend and model choice

### Requirement: Handle absence of any available backend

When no backend is available, the router SHALL NOT return a runnable recommendation and SHALL surface an error that lists the supported backends and how to install them.

#### Scenario: No backend installed

- **WHEN** none of the supported backends report availability
- **THEN** the router raises a clear error naming the supported backends and install guidance
