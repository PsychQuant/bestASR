## MODIFIED Requirements

### Requirement: Common engine interface

Every backend SHALL implement the common engine interface with `is_available() -> bool`, `transcribe(audio_path, options) -> Transcript`, and `estimate_requirements(model_name) -> ModelRequirements`. Transcribe options SHALL carry the model, the quantization variant, and the optional language. The supported backend implementations SHALL be `whisperkit` (CoreML/ANE path) and `whisper.cpp` (GGUF quantized path).

#### Scenario: Each backend exposes the interface

- **WHEN** any supported backend is instantiated
- **THEN** it provides `is_available`, `transcribe`, and `estimate_requirements` with the specified signatures

#### Scenario: Quantization is part of transcribe options

- **WHEN** an engine is asked to transcribe with a quantization variant its backend supports
- **THEN** the engine loads the model matching that quantization variant
