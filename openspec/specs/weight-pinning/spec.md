# weight-pinning Specification

## Purpose
FluidAudio model-weight integrity: TOFU manifest pinning with fail-loud drift detection (#52).

## Requirements

### Requirement: Downloaded model weights verify against the pinned manifest

Before a FluidAudio-backed model is first used in a process, the system SHALL verify every file recorded for that model in the bundled weights manifest: each entry's SHA256 digest SHALL match the file at the same relative path inside the model's cache directory, and a manifest entry whose file is missing from the cache SHALL count as a mismatch. On any mismatch the system SHALL fail loudly with an error naming the model and the offending path — it SHALL NOT silently proceed with drifted weights. Extra files present in the cache but absent from the manifest SHALL NOT fail verification, and manifest entries for repos no engine seam references are inert (the pin script scans the whole cache, which may include residual directories). Where the upstream API separates download from load (Parakeet), verification SHALL run between the two so drifted weights never reach CoreML compilation; where no split exists (diarizer), verification runs immediately after load and before any audio is processed — a documented limitation that protects every subsequent process.

#### Scenario: Pinned model with intact weights loads normally

- **WHEN** the manifest records digests for `parakeet-tdt-0.6b-v3` and every recorded file matches its cache digest
- **THEN** verification passes and the engine loads the model

#### Scenario: A drifted weight file fails loudly

- **WHEN** one recorded file's cache digest differs from the manifest digest
- **THEN** model loading throws an error naming the model and the file
- **AND** no transcription proceeds with the drifted weights

#### Scenario: A missing pinned file is a mismatch

- **WHEN** the manifest records a file that no longer exists in the cache
- **THEN** verification fails the same way as a digest mismatch

### Requirement: Unpinned models warn and proceed (TOFU window)

A model absent from the weights manifest SHALL be allowed to load with a visible warning that names the model and points at the pinning script. This trust-on-first-use window is the documented boundary of the mechanism: the manifest anchors trust at the maintainer's first verified download, and cannot protect a download that was already compromised before pinning.

#### Scenario: A new model family is not deadlocked

- **WHEN** a newly integrated model repo has no manifest entries yet
- **THEN** the engine loads it and emits a warning recommending `scripts/pin-weights.sh`

### Requirement: The pinning script regenerates the manifest from the local cache

`scripts/pin-weights.sh` SHALL produce a deterministically ordered JSON manifest (`{repo: {relativePath: sha256}}`) from the local FluidAudio model cache, writing it to the bundled resource path so a manifest diff in review is the audit trail for any weight change (e.g. a FluidAudio version upgrade re-pins by re-running the script).

#### Scenario: Re-running the script on an unchanged cache is idempotent

- **WHEN** the script runs twice with no cache changes
- **THEN** the second run produces a byte-identical manifest


<!-- @trace
source: fluidaudio-weight-pinning
updated: 2026-07-06
code:
  - Sources/BestASRKit/Supply/WeightVerifier.swift
  - Sources/BestASRKit/Supply/weights-manifest.json
  - scripts/pin-weights.sh
  - Sources/BestASRKit/Engines/ParakeetEngine.swift
  - Sources/BestASRKit/Diarize/DiarizationEngine.swift
  - Sources/BestASRKit/Diarize/SpeakerEnroller.swift
  - Tests/BestASRKitTests/WeightVerifierTests.swift
  - Package.swift
  - README.md
  - CHANGELOG.md
-->
