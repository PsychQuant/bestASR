## ADDED Requirements

### Requirement: Selection accounts for prompt support when context is present

When a context directory is resolved for the run, backend selection SHALL take each candidate's declared prompt capability into account, and SHALL warn when the selected backend declares no prompt support, stating that the supplied context will have no effect on the transcription.

Selection SHALL NOT exclude a backend solely because it declares no prompt support. Whether a lower measured error rate outweighs the loss of context biasing has not been measured, so the system SHALL surface the trade-off rather than decide it silently.

When no context directory is resolved, prompt capability SHALL NOT influence selection.

#### Scenario: Selecting a backend without prompt support warns the user

- **WHEN** a context directory is resolved and selection picks a backend declaring no prompt support
- **THEN** the system emits a warning that the context will not affect this transcription
- **AND** the selected backend is still used

#### Scenario: Prompt capability is ignored when no context is present

- **WHEN** no context directory is resolved
- **THEN** selection proceeds on its existing criteria alone
- **AND** no prompt-capability warning is emitted

#### Scenario: A supporting backend produces no warning

- **WHEN** a context directory is resolved and selection picks a backend declaring prompt support
- **THEN** no prompt-capability warning is emitted
