## MODIFIED Requirements

### Requirement: Common engine interface

Every backend SHALL implement the common engine interface with `is_available() -> bool`, `transcribe(audio_path, options) -> Transcript`, and `estimate_requirements(model_name) -> ModelRequirements`. Transcribe options SHALL carry the model, the quantization variant, the optional language, and an optional context prompt. When a context prompt is present, the engine SHALL forward it to its backend's prompt mechanism (the WhisperKit decode-options prompt path; the whisper-cli prompt flag); when absent, no prompt SHALL be passed. The supported backend implementations SHALL be `whisperkit` (CoreML/ANE path) and `whisper.cpp` (GGUF quantized path).

#### Scenario: Each backend exposes the interface

- **WHEN** any supported backend is instantiated
- **THEN** it provides `is_available`, `transcribe`, and `estimate_requirements` with the specified signatures

#### Scenario: Quantization is part of transcribe options

- **WHEN** an engine is asked to transcribe with a quantization variant its backend supports
- **THEN** the engine loads the model matching that quantization variant

#### Scenario: Context prompt is forwarded to the backend

- **WHEN** an engine is asked to transcribe with options carrying a context prompt
- **THEN** the prompt reaches the backend's prompt mechanism for that run

#### Scenario: Absent prompt adds nothing to the invocation

- **WHEN** an engine is asked to transcribe with options carrying no context prompt
- **THEN** the backend invocation carries no prompt argument and behavior matches the pre-context feature
