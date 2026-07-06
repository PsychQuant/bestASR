# model-grid Specification

## Purpose

TBD - created by archiving change 'mlx-audio-backend-and-bcnf-store'. Update Purpose after archive.

## Requirements

### Requirement: Full-family catalog

The model grid SHALL carry the full-family catalog — the 15-family mlx-audio reference rows untouched — plus live rows for the FluidAudio-backed backends (`fluid-parakeet` parakeet family, `fluid-paraformer` paraformer family, `fluid-sensevoice` sensevoice family, sizes as shipped by the pinned FluidAudio release). Priority-1 live rows enumerate as default benchmark candidates; a live row may sit at a lower tier when its family is wired but not yet usable (e.g. an upstream decode bug), keeping it out of the default sweep. The mlx-audio reference rows carry verified HuggingFace repos with pinned revisions; they become runnable candidates only while a registered external adapter (#51, spec external-engine-protocol) makes the `mlx-audio` backend available — otherwise they stay reference-only.

#### Scenario: Live and reference parakeet rows coexist distinguishably

- **WHEN** the grid is queried for the parakeet family
- **THEN** it returns both the live `fluid-parakeet` row(s) and the reference `mlx-audio` row, distinguishable by backend id

#### Scenario: Reference catalog integrity is preserved

- **WHEN** the grid seeds the store after this change
- **THEN** all 15 mlx-audio reference families remain present with their pinned HF repo/revision metadata, and none enumerate as candidates

#### Scenario: Chinese-family live rows are listed

- **WHEN** the grid is filtered to live-engine backends with no priority ceiling
- **THEN** the `fluid-paraformer` and `fluid-sensevoice` rows appear alongside the whisper and parakeet rows


<!-- @trace
source: chinese-asr-families + external-process-engine
updated: 2026-07-06
code:
  - CHANGELOG.md
  - README.md
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Sources/BestASRKit/CommandCore.swift
  - Sources/BestASRKit/Engines/ChineseFamilyEngine.swift
  - Sources/BestASRKit/Engines/ExternalProcessEngine.swift
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Models/ModelGrid.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Router/Router.swift
  - Tests/BestASRKitTests/ChineseEnginesTests.swift
  - Tests/BestASRKitTests/ExternalEngineTests.swift
  - adapters/mlx-audio/bestasr-mlx-adapter.py
  - adapters/mlx-audio/setup.sh
-->

---
### Requirement: Priority tiers gate the default sweep

Grid rows SHALL carry priority 1, 2, or 3. For runnable backends, rows default to priority 1 and enumerate by default — but a wired-yet-unusable family MAY be shelved at priority 2 so the default sweep never pays its download (#50: paraformer, upstream decode bug); for the mlx-audio reference catalog the tier is retained as historical metadata (the original first-run/representative/deferred selection) and has no enumeration effect. Once an external adapter registers the `mlx-audio` backend (#51), the same priority gate applies to its rows — the default sweep covers priority-1 entries and `--all-grid` widens to the rest.

#### Scenario: default sweep

- **WHEN** a benchmark runs
- **THEN** enumeration covers only runnable backends' rows
- **AND** no mlx-audio reference row appears as a candidate


<!-- @trace
source: chinese-asr-families + external-process-engine
updated: 2026-07-06
code:
  - CHANGELOG.md
  - README.md
  - Sources/BestASRKit/Benchmark/BenchmarkRunner.swift
  - Sources/BestASRKit/CommandCore.swift
  - Sources/BestASRKit/Engines/ChineseFamilyEngine.swift
  - Sources/BestASRKit/Engines/ExternalProcessEngine.swift
  - Sources/BestASRKit/Models/DataModels.swift
  - Sources/BestASRKit/Models/ModelGrid.swift
  - Sources/BestASRKit/Models/ModelRegistry.swift
  - Sources/BestASRKit/Router/Router.swift
  - Tests/BestASRKitTests/ChineseEnginesTests.swift
  - Tests/BestASRKitTests/ExternalEngineTests.swift
  - adapters/mlx-audio/bestasr-mlx-adapter.py
  - adapters/mlx-audio/setup.sh
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