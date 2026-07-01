## ADDED Requirements

### Requirement: Detect Apple Silicon hardware profile

The system SHALL detect the Apple chip name, total unified memory in gigabytes, Apple Neural Engine availability, and the macOS version, exposed on `SystemInfo` as `chip`, `unified_memory_gb`, `has_ane`, and `macos_version`. Detection SHALL use system facilities (sysctl and process information APIs) with no external tool dependency. When ANE availability cannot be determined for an unknown chip generation, the system SHALL report it as unknown rather than failing. When run on a non-Apple-Silicon host (including under Rosetta translation), the system SHALL fail with a clear unsupported-platform error.

#### Scenario: Report chip and unified memory on Apple Silicon

- **WHEN** detection runs on an Apple Silicon Mac
- **THEN** `SystemInfo.chip` is a non-empty string naming the Apple chip
- **AND** `SystemInfo.unified_memory_gb` is a positive number
- **AND** `SystemInfo.macos_version` reflects the running macOS version

#### Scenario: Unknown chip generation degrades ANE to unknown

- **WHEN** detection runs on a chip generation absent from the ANE capability table
- **THEN** `has_ane` reports an unknown state
- **AND** detection completes without raising

#### Scenario: Non-Apple-Silicon host is rejected clearly

- **WHEN** detection runs on a non-Apple-Silicon host
- **THEN** a clear unsupported-platform error is raised naming the requirement for Apple Silicon

## MODIFIED Requirements

### Requirement: Probe audio file properties

The system SHALL probe an audio file for duration, container format, sample rate, and channel count, exposed on `AudioInfo`, using the platform audio framework (AVFoundation) as the source. An unreadable or non-audio file SHALL produce a clear error naming the file.

#### Scenario: Probe a valid audio file

- **WHEN** `AudioInfo` is built for a valid audio file
- **THEN** `duration`, `format`, `sample_rate`, and `channels` are populated with values read from the file

#### Scenario: Unreadable file is rejected clearly

- **WHEN** `AudioInfo` is built for a file that is missing or not decodable as audio
- **THEN** a clear error is raised naming the file

## REMOVED Requirements

### Requirement: Detect operating system and CPU

**Reason**: The multi-OS surface (macOS, Linux, Windows) is obsolete on the Apple Silicon-only target; chip and macOS version detection is subsumed by the Apple hardware profile.
**Migration**: See ADDED "Detect Apple Silicon hardware profile" (`chip`, `macos_version`).

### Requirement: Detect memory and GPU

**Reason**: Discrete GPU and VRAM are not a concept on Apple Silicon; memory is unified.
**Migration**: Unified memory is covered by ADDED "Detect Apple Silicon hardware profile" (`unified_memory_gb`).

### Requirement: Detect acceleration backends

**Reason**: CUDA and MLX availability flags drove the removed cross-platform backend decision table; on Apple Silicon the relevant accelerator signal is the Neural Engine.
**Migration**: ANE availability is covered by ADDED "Detect Apple Silicon hardware profile" (`has_ane`); backend availability itself is probed by the asr-engine capability.

### Requirement: Detect CPU instruction sets and ffmpeg presence

**Reason**: AVX flags are x86-only; the ffmpeg external-tool dependency is removed because audio probing now uses the platform audio framework.
**Migration**: Audio probing is covered by the MODIFIED "Probe audio file properties"; no instruction-set detection is needed on Apple Silicon.

### Requirement: Graceful degradation when a probe tool is unavailable

**Reason**: The optional probe dependencies this requirement covered (psutil, ffmpeg) no longer exist; detection uses always-present system frameworks.
**Migration**: Failure handling for unreadable audio files is covered by the MODIFIED "Probe audio file properties"; unsupported-platform handling is covered by ADDED "Detect Apple Silicon hardware profile".
