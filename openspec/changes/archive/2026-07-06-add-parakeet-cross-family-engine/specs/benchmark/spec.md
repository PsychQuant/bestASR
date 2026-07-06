## MODIFIED Requirements

### Requirement: Compute accuracy metric selected by language

The benchmark SHALL compute the accuracy metric selected by language for every enumerable candidate — including fluid-parakeet — on the same corpora, applying the same text normalization to every hypothesis before computing WER/CER so that scores are comparable across model families with different tokenizer and punctuation conventions.

#### Scenario: Fluid-parakeet enters the measurement matrix

- **WHEN** `bestasr benchmark` runs on a host with the fluid-parakeet engine available
- **THEN** fluid-parakeet candidates are measured and their records persist to the store alongside Whisper records (same schema, backend field distinguishes)

#### Scenario: Family-specific output conventions do not skew scores

- **WHEN** two families emit the same words with different casing/punctuation conventions
- **THEN** both hypotheses normalize to the same comparison form before WER/CER, yielding equal scores
