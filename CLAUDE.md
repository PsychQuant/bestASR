<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

## Conventions

### Context directory — `.bestasr/context/` (post-#107, breaking)

Context bundles (`context.json` + `*.txt`/`*.md` term lists for context biasing) resolve in this order:

1. `--context-dir <dir>` (explicit flag)
2. `./.bestasr/context/` (cwd-relative)
3. `~/.bestasr/context/` (global)

**#107 was a breaking rename**: the legacy cwd layer `./bestasr-context/` was **removed** — the new code (`ContextLoader.cwdDirectoryName = ".bestasr/context"`) no longer reads it. There is **no auto-migration**. A context dir created before #107 sits at a dead path and is silently ignored.

- **Never create a new context dir as `bestasr-context/`** — always `.bestasr/context/`. The `context-ingest` / `transcript` / `srt-proofread` skills already default correctly.
- **Migrating a pre-#107 dir** is a one-line rename (git-tracked → `git mv`):

  ```bash
  git mv bestasr-context .bestasr/context     # or: mkdir -p .bestasr && mv bestasr-context .bestasr/context
  ```

  Verify with `git check-ignore .bestasr/context/context.json` (must NOT be ignored — some repos gitignore `.bestasr/`; if so, carve it back in or keep local).

## References

- **[mlx-audio](https://github.com/Blaizzy/mlx-audio)** — MLX（Apple Silicon 原生）音訊框架，含 15+ 個 STT/ASR 模型家族（Whisper、Distil-Whisper、Qwen3-ASR、Parakeet、Nemotron、Voxtral、Canary、Moonshine、MMS、Granite Speech、Qwen2-Audio、VibeVoice-ASR、Mega-ASR…）與 20+ TTS 模型。`pip install mlx-audio`，提供 CLI / Python API / OpenAI-compatible REST。reference catalog 的資料來源（backend 曾於 #14 實作、#20 經評估後移除——git history 保有完整實作；模型目錄留在 grid 供查閱）。
