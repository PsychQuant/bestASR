## ADDED Requirements

### Requirement: Measure the context-biasing delta

When a context directory is provided, the benchmark SHALL measure each candidate twice — a baseline run without the context prompt and a run with it — and report both error rates plus their delta per candidate, in the table and in the JSON output. Only the baseline record SHALL be persisted to the machine-local cache: context effects vary per audio and per document set, and cached routing data stays context-neutral.

#### Scenario: Delta appears per candidate

- **WHEN** a benchmark runs with a context directory over two candidates
- **THEN** each reported candidate carries a baseline error rate, a with-context error rate, and their delta

##### Example: biasing improves the name-heavy clip

| Candidate       | WER (baseline) | WER (ctx) | Delta  |
| --------------- | -------------- | --------- | ------ |
| whisperkit tiny | 0.25           | 0.15      | -0.10  |

#### Scenario: Cache stays context-neutral

- **WHEN** a context-enabled benchmark completes
- **THEN** the machine-local cache holds the baseline measurements only

#### Scenario: No context directory means no extra runs

- **WHEN** a benchmark runs without a context directory
- **THEN** each candidate is measured once and the report shape is unchanged from the pre-context feature
