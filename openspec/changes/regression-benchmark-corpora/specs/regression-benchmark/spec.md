## ADDED Requirements

### Requirement: Machine-independent regression baseline

The project SHALL keep a version-controlled baseline file (`benchmarks/baseline.json`) recording, per benchmark corpus, the golden accuracy figure and an allowed tolerance for a single fixed reference model. The baseline SHALL record only accuracy (CER for spaceless languages, WER otherwise) and SHALL NOT record speed (times-realtime): accuracy is a text comparison between model output and reference and is machine-independent, whereas speed varies by machine and would produce false regressions across machines or CI. Each baseline entry SHALL name its corpus, language, model, metric kind, golden value, and tolerance. The machine-local benchmark store remains the source of speed and exploratory measurements and is separate from this baseline.

#### Scenario: baseline records accuracy only

- **WHEN** the baseline file is inspected
- **THEN** every entry carries a corpus name, language, the fixed reference model, a metric kind (cer or wer), a golden value, and a tolerance
- **AND** no entry records times-realtime or any machine-specific speed figure

#### Scenario: language code zh denotes Traditional Chinese

- **WHEN** a baseline entry has language `zh`
- **THEN** it refers to the Traditional Chinese (Common Voice zh-TW) corpus, consistent with the corpora standard set

### Requirement: Regression gate fails on accuracy regression

A regression gate script SHALL, for the fixed reference model, transcribe every standard corpus, compute its accuracy metric, compare against the corresponding `benchmarks/baseline.json` entry, and exit non-zero if any corpus's measured accuracy is worse than its golden value by more than the tolerance. The gate SHALL surface, for each regressed corpus, the language, golden value, measured value, and the difference. The gate SHALL judge accuracy only and SHALL NOT fail on speed differences. A corpus present in the standard set but missing a baseline entry SHALL be reported as a gate error rather than silently passing.

#### Scenario: no regression passes

- **WHEN** the gate runs and every corpus's measured accuracy is within its baseline tolerance
- **THEN** the gate exits zero and prints a pass summary

#### Scenario: an accuracy regression fails loudly

- **GIVEN** a baseline whose golden value for one corpus is set beyond reach (simulating a regression)
- **WHEN** the gate runs
- **THEN** it exits non-zero and names that corpus with its language, golden, measured, and difference

#### Scenario: a speed change does not trip the gate

- **WHEN** the reference model runs slower than a previous machine but every accuracy metric is within tolerance
- **THEN** the gate still exits zero (speed is not gated)

#### Scenario: missing baseline entry is a gate error

- **GIVEN** a standard corpus with no matching entry in the baseline
- **WHEN** the gate runs
- **THEN** it reports a gate error for that corpus rather than passing silently
