# asr-routing — delta

## MODIFIED Requirements

### Requirement: Rank candidates by measured benchmark data

When the machine-local benchmark store's latest projection contains measurements for the current machine whose backend is currently available and whose corpus language matches the request, the router SHALL rank those candidates by the active profile weighting over measured error rate and measured RTF and SHALL recommend the highest-ranked candidate, including its quantization. The recommendation SHALL mark its data source as measured. Rankings are per-language: measurements from corpora of other languages SHALL NOT enter the candidate set. Profiles form the ordinal ladder `low` / `medium` / `high` / `xhigh` / `max`; under `max` the speed weight is zero, so the most accurate candidate SHALL win regardless of RTF, and candidates with equal error rates SHALL tie-break to the faster one. Ranking order SHALL be deterministic: equal weighted scores tie-break by higher measured x-realtime, then by lexicographic (backend, model, quantization).

#### Scenario: Measured data drives the recommendation

- **WHEN** the store's latest projection holds matching measurements for whisperkit large-v3-turbo and whisper.cpp small
- **AND** the profile is `high`
- **THEN** the recommendation is the candidate with the better profile-weighted score
- **AND** the recommendation data source is `measured`

##### Example: profile flips the winner on the same measurements

| Candidate                 | CER  | x-realtime | high profile picks | low profile picks |
| ------------------------- | ---- | ---------- | ------------------ | ----------------- |
| whisperkit large-v3-turbo | 0.05 | 12.0       | ✓                  |                   |
| whisper.cpp small q5      | 0.15 | 20.0       |                    | ✓                 |

#### Scenario: max is a pure accuracy argmax with a speed tie-break

- **WHEN** the store holds a 0.05-CER candidate at 2.0x realtime, a 0.06-CER candidate at 40.0x realtime, and a second 0.05-CER candidate at 12.0x realtime
- **AND** the profile is `max`
- **THEN** the recommendation is the 0.05-CER candidate at 12.0x realtime (best error rate wins regardless of speed; the equal-error tie breaks to the faster candidate)

#### Scenario: Stale-machine records are ignored

- **WHEN** every measurement was recorded under a different machine id than the current machine
- **THEN** the router treats the store as empty and falls back to the cold-start prior

#### Scenario: Other-language measurements stay out

- **GIVEN** the request resolves to zh
- **AND** the store holds only en-corpus measurements
- **THEN** the router falls back to the cold-start prior for zh

### Requirement: Cold-start prior when no benchmark data exists

When no usable benchmark record exists for the request, the router SHALL fall back to a static prior: select the preferred available backend (whisperkit first, then whisper.cpp), select the most accurate model in the active profile's candidate list (`low` → tiny/base/small, `medium` → small/medium, `high` / `xhigh` / `max` → medium/large-v3-turbo/large-v3 — the top three tiers share one list because without measured data the ordinals can only differ in measured weighting) whose estimated memory requirement fits unified memory, and mark the recommendation data source as cold-start prior. The reasons SHALL include a suggestion to run the benchmark command for measured, machine-specific recommendations.

#### Scenario: Cold start recommends from the prior and suggests benchmarking

- **WHEN** the benchmark cache is empty and whisperkit is available
- **AND** the profile is `medium`
- **THEN** the recommendation backend is `whisperkit` with a model from the medium candidate list
- **AND** the recommendation data source is `cold_start_prior`
- **AND** `reason` contains an entry suggesting to run the benchmark command
