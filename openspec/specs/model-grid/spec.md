# model-grid Specification

## Purpose

TBD - created by archiving change 'mlx-audio-backend-and-bcnf-store'. Update Purpose after archive.

## Requirements

### Requirement: Full-family catalog

The model grid SHALL enumerate the runnable backends' models as catalog rows and SHALL additionally retain the 15 mlx-audio STT families as a **reference catalog** — rows carrying languages, estimated memory, optional HF repo id with pinned revision, and a historical priority tier. Reference rows are not runnable (no engine is bundled for them) and exist for lookup and potential future reinstatement.

#### Scenario: grid completeness

- **WHEN** the grid is loaded
- **THEN** it contains rows for all 15 mlx-audio families (reference) plus the WhisperKit and whisper.cpp models, totalling at least 30 rows

#### Scenario: reference rows are visible but not runnable

- **WHEN** the model listing renders
- **THEN** the mlx-audio section is labeled as a reference catalog whose backend is not bundled
- **AND** benchmark enumeration produces no candidates from reference rows


<!-- @trace
source: remove-mlx-audio-backend
updated: 2026-07-04
code:
  - Tests/BestASRKitTests/DiarizationTests.swift
  - Sources/BestASRKit/Engines/mlx_worker.py
  - Sources/BestASRKit/Diarize/SpeakerIdentifier.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - Tests/BestASRKitTests/RouterTests.swift
  - Package.swift
  - docs/design-brief.md
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Engines/MLXAudioEngine.swift
  - CHANGELOG.md
  - README.md
  - Sources/BestASRKit/CommandCore.swift
  - Sources/BestASRKit/Diarize/SpeakerAssigner.swift
  - Tests/BestASRKitTests/DataModelTests.swift
  - Package.resolved
  - Sources/BestASRKit/Diarize/SpeakerEnroller.swift
  - Tests/BestASRKitTests/ModelGridTests.swift
  - Tests/BestASRKitTests/PipelineWiringTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Engines/MLXWorkerProtocol.swift
  - scripts/validate-diarization.sh
  - Sources/BestASRKit/Store/StoreTables.swift
  - Sources/BestASRKit/Detect/DynamicHostState.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Models/ModelGrid.swift
  - Sources/BestASRKit/Router/Ranking.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Sources/BestASRKit/Store/BenchmarkStore.swift
  - scripts/fetch-corpora.sh
  - Tests/BestASRKitTests/MLXAudioEngineTests.swift
  - Tests/BestASRKitTests/EffortProfileTests.swift
  - CLAUDE.md
  - Tests/BestASRKitTests/CLITests.swift
  - Sources/BestASRKit/Diarize/DiarizationEngine.swift
  - Sources/bestasr/BestASRCommand.swift
  - Sources/BestASRKit/Router/Router.swift
  - .claude-plugin/marketplace.json
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Output/TranscriptWriter.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Tests/BestASRKitTests/BenchmarkStoreTests.swift
-->

---
### Requirement: Priority tiers gate the default sweep

Grid rows SHALL carry priority 1, 2, or 3. For runnable backends every current row is priority 1 and enumerates by default; for the mlx-audio reference catalog the tier is retained as historical metadata (the original first-run/representative/deferred selection) and has no enumeration effect.

#### Scenario: default sweep

- **WHEN** a benchmark runs
- **THEN** enumeration covers only runnable backends' rows
- **AND** no mlx-audio reference row appears as a candidate


<!-- @trace
source: remove-mlx-audio-backend
updated: 2026-07-04
code:
  - Tests/BestASRKitTests/DiarizationTests.swift
  - Sources/BestASRKit/Engines/mlx_worker.py
  - Sources/BestASRKit/Diarize/SpeakerIdentifier.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - Tests/BestASRKitTests/RouterTests.swift
  - Package.swift
  - docs/design-brief.md
  - plugins/bestasr/skills/context-ingest/SKILL.md
  - Sources/BestASRKit/Engines/MLXAudioEngine.swift
  - CHANGELOG.md
  - README.md
  - Sources/BestASRKit/CommandCore.swift
  - Sources/BestASRKit/Diarize/SpeakerAssigner.swift
  - Tests/BestASRKitTests/DataModelTests.swift
  - Package.resolved
  - Sources/BestASRKit/Diarize/SpeakerEnroller.swift
  - Tests/BestASRKitTests/ModelGridTests.swift
  - Tests/BestASRKitTests/PipelineWiringTests.swift
  - Sources/BestASRKit/Context/ContextLoader.swift
  - Sources/BestASRKit/Engines/MLXWorkerProtocol.swift
  - scripts/validate-diarization.sh
  - Sources/BestASRKit/Store/StoreTables.swift
  - Sources/BestASRKit/Detect/DynamicHostState.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Models/ModelGrid.swift
  - Sources/BestASRKit/Router/Ranking.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Sources/BestASRKit/Store/BenchmarkStore.swift
  - scripts/fetch-corpora.sh
  - Tests/BestASRKitTests/MLXAudioEngineTests.swift
  - Tests/BestASRKitTests/EffortProfileTests.swift
  - CLAUDE.md
  - Tests/BestASRKitTests/CLITests.swift
  - Sources/BestASRKit/Diarize/DiarizationEngine.swift
  - Sources/bestasr/BestASRCommand.swift
  - Sources/BestASRKit/Router/Router.swift
  - .claude-plugin/marketplace.json
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Output/TranscriptWriter.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Tests/BestASRKitTests/BenchmarkStoreTests.swift
-->

---
### Requirement: Unmeasured is a join fact, not a marker

"Enumerated but not yet measured" SHALL be expressed purely as a grid row lacking a corresponding measurement row; the grid SHALL carry no measurement-status field.

#### Scenario: fresh grid row

- **GIVEN** a grid row with no measurement for the current machine
- **THEN** ranking treats it as unmeasured (cold-start eligible) without any explicit flag


<!-- @trace
source: mlx-audio-backend-and-bcnf-store
updated: 2026-07-02
code:
  - Sources/bestasr/BestASRCommand.swift
  - Package.swift
  - Sources/BestASRKit/Corpora/CorpusRegistry.swift
  - scripts/fetch-corpora.sh
  - Sources/BestASRKit/Store/StoreTables.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Engines/mlx_worker.py
  - Sources/BestASRKit/Router/Router.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - Sources/BestASRKit/Engines/MLXAudioEngine.swift
  - Tests/BestASRKitTests/RouterTests.swift
  - .claude-plugin/marketplace.json
  - Sources/BestASRKit/Store/StoreProjection.swift
  - Tests/BestASRKitTests/ModelGridTests.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Models/ModelGrid.swift
  - Sources/BestASRKit/Store/BenchmarkStore.swift
  - README.md
  - Tests/BestASRKitTests/DataModelTests.swift
  - CHANGELOG.md
  - Sources/BestASRKit/Benchmark/BenchmarkCache.swift
  - Sources/BestASRKit/Engines/MLXWorkerProtocol.swift
  - Tests/BestASRKitTests/BenchmarkStoreTests.swift
  - Tests/BestASRKitTests/CLITests.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/MLXAudioEngineTests.swift
  - Sources/BestASRKit/Engines/CreateOnceStore.swift
  - Sources/BestASRKit/CommandCore.swift
-->

---
### Requirement: Unverified repo ids are marked, never guessed

Rows whose HF repo id has not been verified against the hub SHALL carry an explicit unverified marker, and download guidance SHALL never fabricate a repo path for them.

#### Scenario: unverified row guidance

- **WHEN** a transcription is requested for an unverified row
- **THEN** the error directs the user to locate the model on the hub instead of printing a guessed URL

<!-- @trace
source: mlx-audio-backend-and-bcnf-store
updated: 2026-07-02
code:
  - Sources/bestasr/BestASRCommand.swift
  - Package.swift
  - Sources/BestASRKit/Corpora/CorpusRegistry.swift
  - scripts/fetch-corpora.sh
  - Sources/BestASRKit/Store/StoreTables.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Engines/mlx_worker.py
  - Sources/BestASRKit/Router/Router.swift
  - plugins/bestasr/.claude-plugin/plugin.json
  - Sources/BestASRKit/Engines/MLXAudioEngine.swift
  - Tests/BestASRKitTests/RouterTests.swift
  - .claude-plugin/marketplace.json
  - Sources/BestASRKit/Store/StoreProjection.swift
  - Tests/BestASRKitTests/ModelGridTests.swift
  - Tests/BestASRKitTests/BenchmarkTests.swift
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Models/ModelGrid.swift
  - Sources/BestASRKit/Store/BenchmarkStore.swift
  - README.md
  - Tests/BestASRKitTests/DataModelTests.swift
  - CHANGELOG.md
  - Sources/BestASRKit/Benchmark/BenchmarkCache.swift
  - Sources/BestASRKit/Engines/MLXWorkerProtocol.swift
  - Tests/BestASRKitTests/BenchmarkStoreTests.swift
  - Tests/BestASRKitTests/CLITests.swift
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Tests/BestASRKitTests/MLXAudioEngineTests.swift
  - Sources/BestASRKit/Engines/CreateOnceStore.swift
  - Sources/BestASRKit/CommandCore.swift
-->