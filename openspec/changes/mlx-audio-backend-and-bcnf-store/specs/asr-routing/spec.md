## MODIFIED Requirements

### Requirement: Rank candidates by measured benchmark data

When the machine-local benchmark store's latest projection contains measurements for the current machine whose backend is currently available and whose corpus language matches the request, the router SHALL rank those candidates by the active profile weighting over measured error rate and measured RTF and SHALL recommend the highest-ranked candidate, including its quantization. The recommendation SHALL mark its data source as measured. Rankings are per-language: measurements from corpora of other languages SHALL NOT enter the candidate set.

#### Scenario: Measured data drives the recommendation

- **WHEN** the store's latest projection holds matching measurements for whisperkit large-v3-turbo and whisper.cpp small
- **AND** the profile is `accurate`
- **THEN** the recommendation is the candidate with the better profile-weighted score
- **AND** the recommendation data source is `measured`

##### Example: profile flips the winner on the same measurements

| Candidate                 | CER  | x-realtime | accurate profile picks | fast profile picks |
| ------------------------- | ---- | ---------- | ---------------------- | ------------------ |
| whisperkit large-v3-turbo | 0.05 | 12.0       | ✓                      |                    |
| whisper.cpp small q5      | 0.15 | 20.0       |                        | ✓                  |

#### Scenario: Stale-machine records are ignored

- **WHEN** every measurement was recorded under a different machine id than the current machine
- **THEN** the router treats the store as empty and falls back to the cold-start prior

#### Scenario: Other-language measurements stay out

- **GIVEN** the request resolves to zh
- **AND** the store holds only en-corpus measurements
- **THEN** the router falls back to the cold-start prior for zh
