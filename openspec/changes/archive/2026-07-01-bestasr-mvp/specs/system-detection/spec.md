## ADDED Requirements

### Requirement: Detect operating system and CPU

The system SHALL detect the host operating system and CPU model and expose them on `SystemInfo` as `os` and `cpu`.

#### Scenario: Report OS and CPU on any platform

- **WHEN** `diagnose` runs on a supported platform (macOS, Linux, or Windows)
- **THEN** `SystemInfo.os` and `SystemInfo.cpu` are non-empty strings describing the host

### Requirement: Detect memory and GPU

The system SHALL detect total RAM in gigabytes, and, when a discrete GPU is present, the GPU name and VRAM in gigabytes, exposed as `ram_gb`, `gpu`, and `vram_gb`.

#### Scenario: Report RAM on a machine without a discrete GPU

- **WHEN** detection runs on a CPU-only machine
- **THEN** `SystemInfo.ram_gb` is a positive number
- **AND** `SystemInfo.gpu` is null and `SystemInfo.vram_gb` is null

#### Scenario: Report VRAM when an NVIDIA GPU is present

- **WHEN** detection runs on a machine with an NVIDIA GPU
- **THEN** `SystemInfo.gpu` names the GPU and `SystemInfo.vram_gb` is a positive number

### Requirement: Detect acceleration backends

The system SHALL detect whether CUDA, Metal, and MLX acceleration are available, exposed as boolean flags `has_cuda`, `has_metal`, and `has_mlx`. Detection SHALL probe availability by attempting to import or query the relevant package or platform facility, and SHALL NOT require those packages as hard dependencies.

#### Scenario: Detect MLX on Apple Silicon

- **WHEN** detection runs on Apple Silicon with mlx installed
- **THEN** `has_metal` is true and `has_mlx` is true

#### Scenario: Absent acceleration reported as false, not an error

- **WHEN** the probe for a backend raises ImportError or is otherwise unavailable
- **THEN** the corresponding flag is false
- **AND** no exception propagates to the caller

### Requirement: Detect CPU instruction sets and ffmpeg presence

The system SHALL detect AVX2 and AVX512 support and whether the `ffmpeg` executable is on PATH, exposed as `has_avx2`, `has_avx512`, and `has_ffmpeg`.

#### Scenario: Report ffmpeg availability

- **WHEN** detection runs
- **THEN** `has_ffmpeg` is true if and only if an `ffmpeg` executable is resolvable on PATH

### Requirement: Probe audio file properties

The system SHALL probe an audio file for duration, container format, sample rate, and channel count, exposed on `AudioInfo`. When `ffprobe` is available it SHALL be the primary source.

#### Scenario: Probe a valid audio file with ffprobe present

- **WHEN** `AudioInfo` is built for a valid audio file and ffprobe is available
- **THEN** `duration`, `format`, `sample_rate`, and `channels` are populated with values read from the file

### Requirement: Determine transcription language

The system SHALL record the requested language on `AudioInfo.language`. When the caller passes an explicit language it SHALL be used verbatim. When the caller passes `auto`, `AudioInfo.language` SHALL be null and language detection SHALL be deferred to the engine.

#### Scenario: Explicit language is recorded

- **WHEN** the caller requests language `zh`
- **THEN** `AudioInfo.language` equals `zh`

#### Scenario: Auto language defers to engine

- **WHEN** the caller requests language `auto`
- **THEN** `AudioInfo.language` is null

### Requirement: Graceful degradation when a probe tool is unavailable

When a probe dependency (for example `psutil` or `ffmpeg`) is missing, the system SHALL fall back to a lower-fidelity source, populate best-effort values, and record a human-readable note, instead of raising.

#### Scenario: Missing ffmpeg degrades audio probing

- **WHEN** `AudioInfo` is built while `ffmpeg` is absent
- **THEN** format is inferred from the file extension
- **AND** a warning note describing reduced fidelity is available to the caller
