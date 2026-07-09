# Design: gui-app-dual-track

## Decisions

**D1 — SwiftPM-built SwiftUI executable, hand-assembled bundle (no `.xcodeproj`).**
The repo is pure SwiftPM (CI included); adding an Xcode project would create a second build system to keep in sync. A SwiftPM `executableTarget` builds a Mach-O that runs as a real app once placed in a scripted `bestASR.app` skeleton with an `Info.plist`. Trade-off accepted: no asset catalogs / Xcode preview infra; v1 ships without a custom icon (generic icon; `CFBundleIconFile` omitted — recorded in Residue).

**D2 — Progress = stage + elapsed, never a fake percent.**
`CommandCore.transcribe` is a single async call with no progress callback; plumbing per-segment progress through every engine is out of scope. The GUI shows an indeterminate indicator, the active stage ("Transcribing…"), and a live elapsed clock. Honest limitation, documented in the UI copy. (The agent-side long-wait is already solved by #86's async jobs.)

**D3 — v1 flow: one file at a time.**
Picker (`fileImporter`) + drag-and-drop; queueing/batch is future work. Export formats = the existing `OutputFormat` set the core already writes (srt/vtt/txt/json); GUI defaults to SRT. Language picker: auto/zh/ja/en (matches the benchmark languages; free-form codes can come later). Effort picker: `auto` + `RouterProfile` ordinals (low/medium/high/xhigh/max). Defaults persist via `@AppStorage`.

**D4 — Reuse `CommandCore` verbatim; inject a runner closure into the view model.**
The GUI calls `core.transcribe(audioPath:selection:formatName:outputPath:diarize:)` and displays the written file's content plus the outcome explanation. `TranscribeSession` (`@MainActor @Observable`, per swiftui-specialist dataflow guidance) takes a `@Sendable` runner closure so tests drive the full state machine with a fake — no engines, no audio.

**D5 — Bundle identity & contents.**
`Contents/MacOS/` carries `bestASR` (GUI, `CFBundleExecutable`), `bestasr-mcp`, `bestasr`. Bundle id `com.psychquant.bestASR`; `CFBundleShortVersionString` = `BestASRVersion.current` (read at assemble time from `swift run bestasr --version` output or the source constant); `LSMinimumSystemVersion` 14.0 (the package's platform floor); `NSHumanReadableCopyright` PsychQuant. Agents use the helper via `claude mcp add bestasr -- /Applications/bestASR.app/Contents/MacOS/bestasr-mcp`.

**D6 — Signing pipeline mirrors `release-mcp.sh` (#85), extended for bundles.**
Stages: universal build (arm64 + x86_64) → assemble → codesign nested executables first, then the bundle (`--options runtime --timestamp`, Developer ID `$DEVELOPER_ID`) → `ditto`-zip → `notarytool submit --wait` (`$NOTARY_PROFILE`) → **`stapler staple` + `stapler validate`** (the bundle-only capability that motivated this surface) → final zip artifact. `--assemble-only` stops before signing so CI/tests can validate structure without credentials. Signing/notarization run only on the maintainer machine (same posture as release-mcp.sh).

## Implementation Contract

- `TranscribeSession` phases: `idle → running(startedAt) → done(TranscribeOutcome, preview) | failed(message)`; `start` is a no-op while running; `cancel` cancels the awaiting `Task` and returns to idle **and is documented as not necessarily aborting engine inference mid-flight** (engine limitation).
- The GUI never blocks the main thread: the runner executes in a `Task`, UI state mutations happen on `@MainActor`.
- View structure follows swiftui-specialist: one `View` struct per section (drop zone / options / progress / result), narrow inputs, `private @State`, `@Observable` model with `Equatable` stored types.
- `release-app.sh --assemble-only` produces a bundle whose structure a test can assert: three executables present and executable-bit set, `Info.plist` parses, `CFBundleIdentifier`/`CFBundleShortVersionString`/`LSMinimumSystemVersion` correct, GUI binary is `CFBundleExecutable`.
- Failure modes: missing input file → typed core error surfaces in the failed phase verbatim; output directory not writable → failed phase; unknown format impossible (picker constrained).
- Out of scope (v1): batch queue, true percent progress, custom icon, App Store distribution, localization (English UI; strings kept `LocalizedStringKey`-compatible for later).

## Alternatives Considered

- **Xcode project target** — richer app tooling (assets, previews), but a second build system + CI divergence; rejected for v1.
- **`.mcpb` Desktop extension** — already parked in #87's framing (blocking-chat UX for long jobs).
- **Percent progress via engine callbacks** — requires touching every `Engine` conformer + WhisperKit segment callbacks; deferred, revisit with a dedicated issue if users ask.
