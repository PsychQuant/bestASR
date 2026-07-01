## ADDED Requirements

### Requirement: Repository installs as a Claude Code plugin marketplace

The repository SHALL carry a valid marketplace manifest at `.claude-plugin/marketplace.json` listing the bestasr plugin, such that adding the repository as a plugin marketplace in Claude Code succeeds.

#### Scenario: Marketplace add smoke test

- **WHEN** the repository is added as a plugin marketplace (by GitHub slug or local path)
- **THEN** the marketplace registers and lists the bestasr plugin

### Requirement: bestasr plugin packages the agent workflows

The plugin under `plugins/bestasr/` SHALL carry a plugin manifest and exactly two skills in the first version: `context-ingest` and `srt-proofread`.

#### Scenario: Plugin structure is complete

- **WHEN** the plugin directory is inspected
- **THEN** it contains the plugin manifest and the two skill definitions

### Requirement: context-ingest skill produces schema-valid context documents

The `context-ingest` skill SHALL instruct the agent to read documents of arbitrary formats using its own multimodal abilities, distill them into terms, names (with aliases and roles), and phrases, write a version-1 `context.json` into the resolved context directory (same three-layer resolution as the core), and validate the result against the context-calibration schema before finishing.

#### Scenario: Ingestion ends with a valid document

- **WHEN** the skill processes a folder of source documents
- **THEN** the written context.json declares version 1 and loads without validation errors

### Requirement: srt-proofread skill follows the alignment contract

The `srt-proofread` skill SHALL instruct the agent to correct an SRT transcript against the context documents strictly per the context-calibration three-axis alignment contract — per-cue operation, immutable timecodes, evidence-backed edits only, speaker attribution via context names — and to emit the corrected SRT together with a per-cue diff summary.

#### Scenario: Proofreading output shape

- **WHEN** the skill corrects a transcript
- **THEN** the output includes the corrected SRT and a per-cue diff summary
- **AND** every changed cue cites its supporting context evidence

### Requirement: Plugin version tracks the app version

The plugin manifest version SHALL equal the application version constant, and releases SHALL bump both together.

#### Scenario: Version equality is enforced by test

- **WHEN** the test suite runs
- **THEN** a test asserts the plugin manifest version string equals the application version constant
