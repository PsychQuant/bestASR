# parakeet-engine Specification

## Purpose
FluidAudio Parakeet TDT CoreML engine — the third Engine conformer enabling cross-family competition (#35).

## Requirements

### Requirement: ParakeetEngine conforms to the Engine seam

The system SHALL provide a `ParakeetEngine` implementing the `Engine` protocol (`id` / `isAvailable` / `transcribeRaw`) backed by FluidAudio's Parakeet TDT CoreML models, with `BackendID.fluidParakeet` (rawValue `fluid-parakeet`) as its identifier.

#### Scenario: Transcribes 16 kHz mono input into raw segments

- **WHEN** `transcribeRaw` is called with a 16 kHz mono audio path (guaranteed by the AudioNormalizer seam)
- **THEN** the engine returns a `RawTranscription` whose segments carry start/end seconds and text mapped from FluidAudio's ASR output

#### Scenario: Pipeline instance is cached per model key

- **WHEN** `transcribeRaw` runs twice for the same model within one engine lifetime
- **THEN** the FluidAudio ASR manager is created once and reused (no per-call model reload)

### Requirement: Model acquisition is lazy and failure is surfaced

The engine SHALL report `isAvailable() == true` on supported hosts (FluidAudio is compiled in), download models on first use, and surface download or inference failures as `TranscriptionError` — never silent degradation.

#### Scenario: Download failure fails loud

- **WHEN** the Parakeet model download fails (network, disk, revision mismatch)
- **THEN** `transcribeRaw` throws a `TranscriptionError` naming the backend and cause, and the CLI exits non-zero


<!-- @trace
source: add-parakeet-cross-family-engine
updated: 2026-07-06
code:
  - Sources/BestASRKit/Engines/ParakeetEngine.swift
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Models/ModelGrid.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Router/Router.swift
  - Sources/BestASRKit/CommandCore.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ParakeetEngineTests.swift
  - Tests/BestASRKitTests/RouterTests.swift
  - README.md
  - CHANGELOG.md
-->
