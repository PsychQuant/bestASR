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

## References

- **[mlx-audio](https://github.com/Blaizzy/mlx-audio)** — MLX（Apple Silicon 原生）音訊框架，含 15+ 個 STT/ASR 模型家族（Whisper、Distil-Whisper、Qwen3-ASR、Parakeet、Nemotron、Voxtral、Canary、Moonshine、MMS、Granite Speech、Qwen2-Audio、VibeVoice-ASR、Mega-ASR…）與 20+ TTS 模型。`pip install mlx-audio`，提供 CLI / Python API / OpenAI-compatible REST。候選第三 backend 與 benchmark 模型池擴充來源（見對應 issue）。
