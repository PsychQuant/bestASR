# Proposal: macOS GUI .app dual-track bundle

## Why

bestASR reaches agents well (CLI, Claude Code plugin, MCP server with async jobs #86) but has no human-facing surface: a person who wants "drag an audio file → get an SRT" must use a terminal or sit in a blocking chat. A Claude Desktop `.mcpb` was evaluated and parked for exactly that UX reason (#87). A signed macOS GUI app is the better human vehicle — and the same bundle can carry the MCP helper and CLI, making one notarized, **stapled** artifact serve humans and agents alike (bare `~/bin` binaries cannot be stapled; a real `.app` bundle can, enabling offline Gatekeeper verification).

## What Changes

- New SwiftPM executable target `bestasr-gui`: a SwiftUI macOS app (file picker + drag-and-drop, language/effort/format selection, stage+elapsed progress, result view with export and reveal-in-Finder, persisted defaults) that calls the same `CommandCore` as the CLI/MCP.
- New `scripts/release-app.sh`: universal build → hand-assembled `bestASR.app` bundle (GUI + `bestasr-mcp` + `bestasr-cli` in `Contents/MacOS/`; the CLI is suffixed to dodge the case-insensitive-APFS collision with `bestASR`) → Developer ID sign (nested-first, hardened runtime) → notarize (`che-mcps-notary`) → **staple** → zip artifact. An unsigned assemble mode keeps bundle structure testable without credentials.
- Bundle-structure smoke test + GUI view-model state-machine tests.
- README gains the .app install track.

**Additive**: the CLI, MCP server, and Claude Code plugin (`~/bin` auto-download) are untouched.

## Impact

- Affected specs: new capability `gui-app` (ADDED requirements only).
- Affected code: `Package.swift` (+1 target), new `Sources/bestasr-gui/`, new `scripts/release-app.sh`, `Tests/` additions, README.
- Humans get a no-terminal install (drag to /Applications); agents may point `claude mcp add` at the bundled `bestasr-mcp` path; models still download at first use (~GBs to the existing cache) — the bundle stays small.

Refs #87.
