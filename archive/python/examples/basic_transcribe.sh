#!/usr/bin/env bash
# Transcribe an audio file with the auto-chosen backend/model, and show why.
set -euo pipefail

AUDIO="${1:-input.mp3}"

# Auto-select everything, write SRT subtitles, and explain the choice.
bestasr transcribe "$AUDIO" --format srt --explain
