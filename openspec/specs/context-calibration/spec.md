# context-calibration Specification

## Purpose

TBD - created by archiving change 'context-calibration-and-marketplace'. Update Purpose after archive.

## Requirements

### Requirement: Resolve the context directory by three-layer precedence

The system SHALL resolve the context directory in this order, first hit wins, no merging across layers: an explicit `--context-dir` flag; a `bestasr-context` directory in the current working directory; a global `context` directory under the user's `.bestasr` home directory. The resolved location (or the absence of any) SHALL be stated in the recommendation reasons.

#### Scenario: Explicit flag wins over both fallback layers

- **WHEN** `--context-dir /tmp/ctx` is passed and both the cwd and global directories also exist
- **THEN** only `/tmp/ctx` is loaded

#### Scenario: Working-directory layer wins over the global layer

- **WHEN** no flag is passed and both `./bestasr-context/` and the global directory exist
- **THEN** only `./bestasr-context/` is loaded

#### Scenario: No layer present means no context

- **WHEN** no flag is passed and neither fallback directory exists
- **THEN** no context is loaded and transcription behavior is unchanged


<!-- @trace
source: context-calibration-and-marketplace
updated: 2026-07-02
code:
  - Sources/BestASRKit/Models/DataModels.swift
  - Tests/BestASRKitTests/PluginTests.swift
  - Sources/BestASRKit/Context/ContextSchema.swift
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Context/PromptRenderer.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ContextTests.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - README.md
  - .claude-plugin/marketplace.json
  - Tests/BestASRKitTests/DataModelTests.swift
  - Sources/BestASRKit/CommandCore.swift
  - plugins/bestasr/skills/srt-proofread/SKILL.md
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/CLITests.swift
-->

---
### Requirement: Load and validate the context.json schema

The system SHALL load `context.json` from the resolved directory and validate it: `version` is required and version 1 is the supported value; `language`, `terms`, `names` (objects with `name`, optional `aliases`, optional `role`), `phrases`, and `notes` are optional. An unknown version or a malformed file SHALL produce a clear usage error naming the file. The `notes` field SHALL NOT contribute to the rendered prompt.

#### Scenario: Valid v1 file loads

- **WHEN** the directory contains a valid version-1 context.json
- **THEN** its terms, names, and phrases are available for prompt rendering

##### Example: canonical v1 document

- **GIVEN** context.json containing version 1, terms ["benchmark-driven", "CoreML"], names [{"name": "鄭澈", "aliases": ["Che"], "role": "主持人"}], and notes "for the proofreading agent"
- **WHEN** it is loaded
- **THEN** two terms, one name with one alias, and zero phrases are available, and the notes text is excluded from rendering

#### Scenario: Unknown version is rejected clearly

- **WHEN** context.json declares version 99
- **THEN** a usage error names the file and states that version 1 is supported

#### Scenario: Malformed JSON is rejected clearly

- **WHEN** context.json is not valid JSON
- **THEN** a usage error names the file


<!-- @trace
source: context-calibration-and-marketplace
updated: 2026-07-02
code:
  - Sources/BestASRKit/Models/DataModels.swift
  - Tests/BestASRKitTests/PluginTests.swift
  - Sources/BestASRKit/Context/ContextSchema.swift
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Context/PromptRenderer.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ContextTests.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - README.md
  - .claude-plugin/marketplace.json
  - Tests/BestASRKitTests/DataModelTests.swift
  - Sources/BestASRKit/CommandCore.swift
  - plugins/bestasr/skills/srt-proofread/SKILL.md
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/CLITests.swift
-->

---
### Requirement: Merge plain-text term lists

The system SHALL read `.txt` and `.md` files in the resolved directory as term lists — one term per line, skipping blank lines and lines starting with `#` — and merge them into the term pool after context.json terms.

#### Scenario: txt terms join the pool

- **WHEN** the directory contains terms.txt with three non-blank lines
- **THEN** those three terms are appended to the term pool


<!-- @trace
source: context-calibration-and-marketplace
updated: 2026-07-02
code:
  - Sources/BestASRKit/Models/DataModels.swift
  - Tests/BestASRKitTests/PluginTests.swift
  - Sources/BestASRKit/Context/ContextSchema.swift
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Context/PromptRenderer.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ContextTests.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - README.md
  - .claude-plugin/marketplace.json
  - Tests/BestASRKitTests/DataModelTests.swift
  - Sources/BestASRKit/CommandCore.swift
  - plugins/bestasr/skills/srt-proofread/SKILL.md
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/CLITests.swift
-->

---
### Requirement: Loudly ignore unsupported document formats

Files in the resolved directory with unsupported extensions (for example pdf, docx, pptx, images) SHALL NOT be parsed, SHALL be listed as ignored, and the explain output SHALL direct the user to the context-ingest skill for conversion. Ignoring SHALL never be silent.

#### Scenario: A pdf in the folder is surfaced, not parsed

- **WHEN** the directory contains lecture.pdf
- **THEN** the file appears in the ignored list with guidance to run the context-ingest skill
- **AND** its contents do not affect the prompt


<!-- @trace
source: context-calibration-and-marketplace
updated: 2026-07-02
code:
  - Sources/BestASRKit/Models/DataModels.swift
  - Tests/BestASRKitTests/PluginTests.swift
  - Sources/BestASRKit/Context/ContextSchema.swift
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Context/PromptRenderer.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ContextTests.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - README.md
  - .claude-plugin/marketplace.json
  - Tests/BestASRKitTests/DataModelTests.swift
  - Sources/BestASRKit/CommandCore.swift
  - plugins/bestasr/skills/srt-proofread/SKILL.md
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/CLITests.swift
-->

---
### Requirement: Render context into a natural-language prompt with priority and budget

The system SHALL render context values into a comma-separated natural-language vocabulary list — never JSON — in the priority order names (with aliases) first, then terms, then phrases, subject to a token budget of approximately 200 tokens (tokenizer-measured on the WhisperKit path; a conservative character heuristic on the whisper-cli path). Items that do not fit SHALL be skipped whole and recorded as truncated.

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


<!-- @trace
source: context-calibration-and-marketplace
updated: 2026-07-02
code:
  - Sources/BestASRKit/Models/DataModels.swift
  - Tests/BestASRKitTests/PluginTests.swift
  - Sources/BestASRKit/Context/ContextSchema.swift
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Context/PromptRenderer.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ContextTests.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - README.md
  - .claude-plugin/marketplace.json
  - Tests/BestASRKitTests/DataModelTests.swift
  - Sources/BestASRKit/CommandCore.swift
  - plugins/bestasr/skills/srt-proofread/SKILL.md
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/CLITests.swift
-->

---
### Requirement: Zero impact when context is absent

When no context directory resolves or the resolved directory yields no values, transcription, recommendation, and benchmarking SHALL behave identically to a build without the context feature.

#### Scenario: Empty directory changes nothing

- **WHEN** the resolved directory exists but contains no context.json and no term lists
- **THEN** no prompt is injected and outputs are identical to the no-context behavior


<!-- @trace
source: context-calibration-and-marketplace
updated: 2026-07-02
code:
  - Sources/BestASRKit/Models/DataModels.swift
  - Tests/BestASRKitTests/PluginTests.swift
  - Sources/BestASRKit/Context/ContextSchema.swift
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Context/PromptRenderer.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ContextTests.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - README.md
  - .claude-plugin/marketplace.json
  - Tests/BestASRKitTests/DataModelTests.swift
  - Sources/BestASRKit/CommandCore.swift
  - plugins/bestasr/skills/srt-proofread/SKILL.md
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/CLITests.swift
-->

---
### Requirement: Explain discloses context usage

When context was loaded, the explain output SHALL disclose: the resolved directory, the injected values (count and items), the truncated items (when any), and the ignored files (when any).

#### Scenario: Explain shows what was injected and what was skipped

- **WHEN** transcription runs with a context directory containing values, an over-budget phrase, and a pdf
- **THEN** explain lists the injected values, the truncated phrase, and the ignored pdf with conversion guidance


<!-- @trace
source: context-calibration-and-marketplace
updated: 2026-07-02
code:
  - Sources/BestASRKit/Models/DataModels.swift
  - Tests/BestASRKitTests/PluginTests.swift
  - Sources/BestASRKit/Context/ContextSchema.swift
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Context/PromptRenderer.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ContextTests.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - README.md
  - .claude-plugin/marketplace.json
  - Tests/BestASRKitTests/DataModelTests.swift
  - Sources/BestASRKit/CommandCore.swift
  - plugins/bestasr/skills/srt-proofread/SKILL.md
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/CLITests.swift
-->

---
### Requirement: SRT three-axis alignment contract for post-ASR correction

Post-ASR correction against context documents SHALL align on three axes — speaker, timestamp, and text. Normative rules for any corrector (including the srt-proofread skill): correction operates per SRT cue; cue start and end timecodes SHALL NOT be altered; text SHALL be changed only with supporting context evidence (a matching term, name, or alias); speaker attribution SHALL use the context `names` entries with their roles; the corrector SHALL emit a per-cue diff summary alongside the corrected SRT.

#### Scenario: Timecodes survive correction untouched

- **WHEN** a corrector fixes a mis-heard name inside a cue
- **THEN** the cue's start and end timecodes are byte-identical to the input

#### Scenario: Unsupported edits are refused

- **WHEN** a candidate edit has no supporting term, name, or alias in the context
- **THEN** the cue text is left unchanged

##### Example: name correction with evidence

- **GIVEN** a cue "00:00:01,000 --> 00:00:02,500 / 正撤說可以開始" and context names containing 鄭澈 with alias Che
- **WHEN** the corrector runs
- **THEN** the cue becomes "00:00:01,000 --> 00:00:02,500 / 鄭澈說可以開始" and the diff records 正撤 → 鄭澈

<!-- @trace
source: context-calibration-and-marketplace
updated: 2026-07-02
code:
  - Sources/BestASRKit/Models/DataModels.swift
  - Tests/BestASRKitTests/PluginTests.swift
  - Sources/BestASRKit/Context/ContextSchema.swift
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Context/PromptRenderer.swift
  - Sources/bestasr/BestASRCommand.swift
  - Tests/BestASRKitTests/ContextTests.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - README.md
  - .claude-plugin/marketplace.json
  - Tests/BestASRKitTests/DataModelTests.swift
  - Sources/BestASRKit/CommandCore.swift
  - plugins/bestasr/skills/srt-proofread/SKILL.md
  - Sources/BestASRKit/Engines/WhisperCppEngine.swift
  - Sources/BestASRKit/Benchmark/BenchmarkReport.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Engines/WhisperKitEngine.swift
  - Tests/BestASRKitTests/BackendEngineTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/CLITests.swift
-->

---
### Requirement: Enrollment voices folder is reserved, local-only, and outside document parsing

The resolved context directory MAY contain a `voices/` subfolder holding speaker-enrollment audio samples named `<label>.<audio-ext>` (wav, m4a, mp3); the filename stem is the label used verbatim by the diarization capability for matching speakers. Files under `voices/` are NOT context documents: they SHALL NOT be parsed as terms, SHALL NOT appear in the unsupported-format ignored list, and SHALL NOT influence the rendered prompt. Enrollment samples and any embeddings derived from them are sensitive biometric data: tooling (including the context-ingest skill) SHALL NOT upload, commit, or otherwise transmit them off the local machine. Explain output SHALL disclose how many enrollment voices were found when diarization uses them.

#### Scenario: voices are consumed by diarization, not by the prompt

- **GIVEN** a resolved context directory containing `voices/Alice.wav` and `context.json`
- **WHEN** transcription runs with diarization enabled
- **THEN** the prompt renders from `context.json` unaffected by the voice file, and segments matching the enrolled voice are labeled `Alice`

#### Scenario: voices folder never leaves the machine

- **WHEN** any bestASR tooling (CLI or plugin skills) processes a context directory containing `voices/`
- **THEN** no voice sample or derived embedding is uploaded, committed, or transmitted anywhere
