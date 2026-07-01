#!/usr/bin/env bash
# Print a JSON recommendation (backend / model / compute_type / reason) for an
# audio file, without running transcription.
set -euo pipefail

AUDIO="${1:-input.mp3}"
bestasr recommend "$AUDIO"
