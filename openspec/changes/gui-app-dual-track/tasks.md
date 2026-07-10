# Tasks: gui-app-dual-track

## 1. Target scaffolding

- [x] 1.1 `Package.swift`: add `bestasr-gui` executableTarget (depends on BestASRKit); builds on macOS 14 floor

## 2. GUI (swiftui-specialist loaded — @Observable/@MainActor, per-section View structs, narrow inputs)

- [x] 2.1 `TranscribeSession` (@MainActor @Observable): phase machine idle/running/done/failed with Equatable payloads, injected @Sendable runner closure over `CommandCore.transcribe`, single-flight start, cancel (documented as not aborting engine inference mid-flight)
- [x] 2.2 App entry + `ContentView` composing per-section views: drop zone/picker (fileImporter + onDrop), options bar (language, effort auto+RouterProfile, format), progress section (stage + elapsed via TimelineView), result section (transcript preview, output path, explanation, reveal-in-Finder)
- [x] 2.3 Defaults persistence via @AppStorage (language/effort/format); failure state renders typed core error verbatim

## 3. Bundle + signing pipeline

- [x] 3.1 `scripts/release-app.sh`: universal build → assemble bestASR.app (Info.plist: com.psychquant.bestASR, version = BestASRVersion.current, LSMinimumSystemVersion 14.0; three executables in Contents/MacOS — CLI copied as bestasr-cli, case-insensitive-APFS collision with bestASR) → sign nested-first (hardened runtime, $DEVELOPER_ID) → notarize ($NOTARY_PROFILE) → staple + `stapler validate` → zip; `--assemble-only` unsigned mode
- [x] 3.2 Bundle smoke test: assemble-only run asserts structure (3 executables + exec bits, Info.plist keys, GUI is CFBundleExecutable, version matches BestASRVersion.current)

## 4. Tests

- [x] 4.1 `TranscribeSessionTests`: fake-runner state machine (success → done with preview; thrown core error → failed with message; single-flight while running; cancel returns to idle)

## 5. Docs

- [x] 5.1 README: the .app human-facing track (install, agent use of bundled bestasr-mcp path, model-download note); doc-sync per repo discipline
