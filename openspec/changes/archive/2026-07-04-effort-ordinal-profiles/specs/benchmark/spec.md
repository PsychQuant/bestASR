# benchmark — delta

## MODIFIED Requirements

### Requirement: Rank candidates and report results

The benchmark SHALL rank successfully measured candidates by the active profile weighting over accuracy and speed and SHALL print a report table containing, per candidate: backend, model, quantization, error rate with metric kind, times-realtime, peak memory, and rank. A machine-readable JSON output mode SHALL be available. The `--profile` flag accepts the ordinal ladder `low` / `medium` / `high` / `xhigh` / `max` (report-ranking semantics, default `medium`; the `auto` sentinel is a transcribe/recommend concept and is not accepted here). Ranking order SHALL be deterministic: equal weighted scores tie-break by higher measured x-realtime, then by lexicographic (backend, model, quantization).

#### Scenario: Report contains ranked rows

- **WHEN** three candidates complete measurement
- **THEN** the report lists three rows each carrying backend, model, quantization, error rate, times-realtime, peak memory, and a distinct rank

##### Example: accuracy-first ranking under the high profile

| Candidate                     | CER  | x-realtime | Rank (high profile) |
| ----------------------------- | ---- | ---------- | ------------------- |
| whisperkit large-v3-turbo     | 0.05 | 12.0       | 1                   |
| whisper.cpp large-v3 q5       | 0.06 | 6.0        | 2                   |
| whisper.cpp small q5          | 0.15 | 20.0       | 3                   |
