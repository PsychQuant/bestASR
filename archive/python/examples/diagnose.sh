#!/usr/bin/env bash
# Show what bestASR detects about this machine and what it recommends.
# Works even with no ASR backend installed — it will tell you what to install.
set -euo pipefail

bestasr diagnose
