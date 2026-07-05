## MODIFIED Requirements

### Requirement: Common engine interface

Every ASR backend SHALL implement the common `Engine` interface (`id`, `isAvailable`, `transcribeRaw`), and `BackendID` SHALL enumerate exactly the backends with a bundled runtime: `whisperkit`, `whisper.cpp`, and `fluid-parakeet`.

#### Scenario: Three backends enumerate

- **WHEN** `BackendID.allCases` is consulted (e.g. by `list-backends`)
- **THEN** it yields `whisperkit`, `whisper.cpp`, and `fluid-parakeet`, each constructible as an engine

#### Scenario: Non-Whisper engine inherits the normalization seam

- **WHEN** any input that is not 16 kHz mono is transcribed through `Engine.transcribe` with the fluid-parakeet backend
- **THEN** the engine's `transcribeRaw` receives the normalized 16 kHz mono path (AudioNormalizer, #36), identical to the Whisper backends
