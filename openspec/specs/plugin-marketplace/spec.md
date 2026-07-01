# plugin-marketplace Specification

## Purpose

TBD - created by archiving change 'context-calibration-and-marketplace'. Update Purpose after archive.

## Requirements

### Requirement: Repository installs as a Claude Code plugin marketplace

The repository SHALL carry a valid marketplace manifest at `.claude-plugin/marketplace.json` listing the bestasr plugin, such that adding the repository as a plugin marketplace in Claude Code succeeds.

#### Scenario: Marketplace add smoke test

- **WHEN** the repository is added as a plugin marketplace (by GitHub slug or local path)
- **THEN** the marketplace registers and lists the bestasr plugin


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
### Requirement: bestasr plugin packages the agent workflows

The plugin under `plugins/bestasr/` SHALL carry a plugin manifest and exactly two skills in the first version: `context-ingest` and `srt-proofread`.

#### Scenario: Plugin structure is complete

- **WHEN** the plugin directory is inspected
- **THEN** it contains the plugin manifest and the two skill definitions


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
### Requirement: context-ingest skill produces schema-valid context documents

The `context-ingest` skill SHALL instruct the agent to read documents of arbitrary formats using its own multimodal abilities, distill them into terms, names (with aliases and roles), and phrases, write a version-1 `context.json` into the resolved context directory (same three-layer resolution as the core), and validate the result against the context-calibration schema before finishing.

#### Scenario: Ingestion ends with a valid document

- **WHEN** the skill processes a folder of source documents
- **THEN** the written context.json declares version 1 and loads without validation errors


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
### Requirement: srt-proofread skill follows the alignment contract

The `srt-proofread` skill SHALL instruct the agent to correct an SRT transcript against the context documents strictly per the context-calibration three-axis alignment contract — per-cue operation, immutable timecodes, evidence-backed edits only, speaker attribution via context names — and to emit the corrected SRT together with a per-cue diff summary.

#### Scenario: Proofreading output shape

- **WHEN** the skill corrects a transcript
- **THEN** the output includes the corrected SRT and a per-cue diff summary
- **AND** every changed cue cites its supporting context evidence


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
### Requirement: Plugin version tracks the app version

The plugin manifest version SHALL equal the application version constant, and releases SHALL bump both together.

#### Scenario: Version equality is enforced by test

- **WHEN** the test suite runs
- **THEN** a test asserts the plugin manifest version string equals the application version constant

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