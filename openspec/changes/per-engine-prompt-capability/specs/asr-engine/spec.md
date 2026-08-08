## MODIFIED Requirements

### Requirement: Common engine interface

Every ASR backend SHALL implement the common `Engine` interface (`id`, `isAvailable`, `transcribeRaw`, `promptCapability`), and `BackendID` SHALL enumerate exactly the backends with a bundled runtime: `whisperkit`, `whisper.cpp`, and `fluid-parakeet`.

`promptCapability` SHALL declare whether the backend consumes a decoder conditioning prompt, as one of exactly two states: unsupported, or supported with a maximum token count. The interface SHALL NOT provide a default implementation of `promptCapability`, so that every current and future backend is required to declare it explicitly rather than inherit a silent default.

A backend that declares support with a maximum token count of zero SHALL be treated identically to a backend that declares no support.

#### Scenario: Three backends enumerate

- **WHEN** `BackendID.allCases` is consulted (e.g. by `list-backends`)
- **THEN** it yields `whisperkit`, `whisper.cpp`, and `fluid-parakeet`, each constructible as an engine

#### Scenario: Non-Whisper engine inherits the normalization seam

- **WHEN** any input that is not 16 kHz mono is transcribed through `Engine.transcribe` with the fluid-parakeet backend
- **THEN** the engine's `transcribeRaw` receives the normalized 16 kHz mono path (AudioNormalizer, #36), identical to the Whisper backends

#### Scenario: Every backend declares its prompt capability

- **WHEN** each engine conforming to `Engine` is consulted for `promptCapability`
- **THEN** the two Whisper-family backends declare support with a maximum of 224 tokens
- **AND** every other backend declares no support

#### Scenario: A declared capability matches what the backend actually does

- **WHEN** an engine declares support for a prompt
- **THEN** that engine forwards the rendered prompt to its underlying runtime
- **AND** an engine that declares no support never receives a rendered prompt

#### Scenario: A zero-token budget is treated as no support

- **WHEN** an engine declares support with a maximum token count of zero
- **THEN** the system takes the same path as for an unsupported engine
- **AND** no empty prompt is passed to the backend
