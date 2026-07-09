## ADDED Requirements

### Requirement: SwiftUI GUI transcribes a chosen audio file

The system SHALL provide a SwiftUI macOS app (`bestasr-gui` target) through which a person selects one audio file (file picker or drag-and-drop), chooses language (auto/zh/ja/en), effort profile (auto plus the RouterProfile ordinals), and output format (the existing OutputFormat set), and runs a transcription through the same `CommandCore` the CLI uses. While running, the app SHALL show an indeterminate progress indicator with the active stage and a live elapsed clock (never a fabricated percentage). On completion the app SHALL show the transcript content, the output file path, and the routing explanation, and SHALL offer reveal-in-Finder. Failures SHALL surface the typed core error message in the UI, never silently. Selected defaults (language, effort, format) SHALL persist across launches.

#### Scenario: Happy-path transcription

- **WHEN** a user drops an audio file and starts transcription with default settings
- **THEN** the UI enters a running state (stage + elapsed visible), and on success shows the transcript preview, output path, and explanation

#### Scenario: Failure is loud

- **WHEN** the core throws (e.g. the input file disappeared before start)
- **THEN** the UI shows the typed error message in a failed state and allows starting over

#### Scenario: Start is single-flight

- **WHEN** a transcription is already running
- **THEN** a second start request is a no-op until the current run finishes or is cancelled

### Requirement: Dual-track bundle carries GUI, MCP helper, and CLI

The release artifact SHALL be a single `bestASR.app` bundle whose `Contents/MacOS/` contains exactly three executables: `bestASR` (the GUI, the bundle's `CFBundleExecutable`), `bestasr-mcp`, and `bestasr`. The bundle SHALL declare `CFBundleIdentifier` `com.psychquant.bestASR`, a `CFBundleShortVersionString` equal to `BestASRVersion.current`, and `LSMinimumSystemVersion` 14.0. The bundled `bestasr-mcp` SHALL be usable directly by MCP clients via its bundle path.

#### Scenario: Bundle structure is assembled

- **WHEN** the release script assembles the bundle (unsigned assemble mode included)
- **THEN** the three executables are present with the executable bit set, and the Info.plist parses with the required identifier, version, and minimum-system values

#### Scenario: Version tracks the app version

- **WHEN** the bundle is assembled
- **THEN** its `CFBundleShortVersionString` equals `BestASRVersion.current` (no drift)

### Requirement: Release pipeline signs, notarizes, and staples the bundle

The release script SHALL build universal (arm64 + x86_64) binaries, sign every nested executable and then the bundle with Developer ID and hardened runtime, submit for notarization, and **staple the ticket to the bundle**, validating the staple before producing the final zip artifact. The script SHALL provide an assemble-only mode that stops before signing so bundle structure remains testable without signing credentials. Signing and notarization failures SHALL abort loudly (no unsigned artifact published).

#### Scenario: Stapled artifact verifies offline

- **WHEN** the full release pipeline completes
- **THEN** `stapler validate` succeeds on the bundle before the artifact is zipped

#### Scenario: Assemble-only mode needs no credentials

- **WHEN** the script runs in assemble-only mode on a machine without the Developer ID identity
- **THEN** it produces an unsigned, structurally complete bundle and exits success

### Requirement: The GUI surface is additive

Shipping the GUI bundle SHALL NOT change the behavior of the existing CLI, the MCP stdio server, or the Claude Code plugin's `~/bin` auto-download distribution.

#### Scenario: Existing surfaces unchanged

- **WHEN** the GUI target and release script land
- **THEN** existing CLI/MCP/plugin tests pass unchanged (no behavioral diff in those surfaces)
