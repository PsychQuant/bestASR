## MODIFIED Requirements

### Requirement: Render context into a natural-language prompt with priority and budget

The system SHALL render context values into a comma-separated natural-language vocabulary list — never JSON — in the priority order names (with aliases) first, then terms, then phrases, subject to the token budget declared by the selected engine's `promptCapability` (tokenizer-measured on the WhisperKit path; a conservative character heuristic on the whisper-cli path). Items that do not fit SHALL be skipped whole and recorded as truncated.

The budget SHALL be obtained from the selected engine rather than from a single global constant, so that a backend whose practical limit differs is not held to another backend's limit.

When the selected engine declares no prompt support, the system SHALL NOT render a prompt at all, and SHALL NOT compute or report truncation.

Where the rendering priority order and any engine-side token clamping interact, the clamp SHALL preserve the highest-priority items, so that names are never dropped in favour of phrases.

#### Scenario: Rendering follows the priority order

- **WHEN** context has names, terms, and phrases within budget
- **THEN** the prompt lists all names and aliases first, then terms, then phrases

##### Example: worked example from the design discussion

- **GIVEN** names [{"name": "鄭澈", "aliases": ["Che"], "role": "主持人"}] and terms ["benchmark-driven", "CoreML"]
- **WHEN** the prompt is rendered
- **THEN** the prompt is exactly "鄭澈, Che, benchmark-driven, CoreML"

#### Scenario: Budget overflow drops lowest-priority items first and records them

- **WHEN** the combined values exceed the budget
- **THEN** phrases are dropped before terms and terms before names
- **AND** every dropped item is recorded in the truncation list

#### Scenario: The budget comes from the selected engine

- **WHEN** context is rendered for a backend declaring a maximum of 224 tokens
- **THEN** the rendering budget used is 224
- **AND** it is not the previously hardcoded global value of 200

#### Scenario: No rendering happens for a backend without prompt support

- **WHEN** a context directory holds values and the selected backend declares no prompt support
- **THEN** no prompt is rendered
- **AND** no truncation list is produced

#### Scenario: Engine-side clamping keeps the highest-priority items

- **WHEN** a rendered prompt exceeds the engine's own token clamp
- **THEN** the retained tokens are those of the highest-priority items
- **AND** names are not discarded while lower-priority phrases are retained

### Requirement: Explain discloses context usage

When context was loaded, the explain output SHALL disclose: the resolved directory, the injected values (count and items), the truncated items (when any), and the ignored files (when any).

When the selected engine declares no prompt support, the explain output SHALL state that the backend does not support context biasing, and SHALL NOT report injected or truncated values — reporting an injection count for a backend that discards the prompt misrepresents what the system did.

#### Scenario: Explain shows what was injected and what was skipped

- **WHEN** transcription runs with a context directory containing values, an over-budget phrase, and a pdf
- **THEN** explain lists the injected values, the truncated phrase, and the ignored pdf with conversion guidance

#### Scenario: Explain does not claim injection for an unsupported backend

- **WHEN** transcription runs with a populated context directory on a backend declaring no prompt support
- **THEN** explain states that the backend does not support context biasing
- **AND** explain reports no injected count and no truncated list
