#!/bin/bash
# pin-weights.sh — regenerate the FluidAudio weights manifest from the local
# model cache (#52, spec weight-pinning). The manifest diff in review is the
# audit trail for any weight change; a FluidAudio upgrade re-pins by re-running
# this script. Deterministic ordering → re-running on an unchanged cache is
# byte-identical (spec scenario).
#
# Usage: scripts/pin-weights.sh [repo ...]   (default: every repo in the cache)
set -euo pipefail

CACHE="${FLUIDAUDIO_CACHE:-$HOME/Library/Application Support/FluidAudio/Models}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/Sources/BestASRKit/Supply/weights-manifest.json"

[ -d "$CACHE" ] || { echo "✗ no FluidAudio cache at: $CACHE" >&2; exit 1; }

if [ $# -gt 0 ]; then
  REPOS=("$@")
else
  REPOS=()
  while IFS= read -r d; do REPOS+=("$(basename "$d")"); done \
    < <(find "$CACHE" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
fi

{
  echo "{"
  first_repo=true
  for repo in "${REPOS[@]}"; do
    dir="$CACHE/$repo"
    [ -d "$dir" ] || { echo "✗ repo not in cache: $repo" >&2; exit 1; }
    $first_repo || echo ","
    first_repo=false
    printf '  "%s": {\n' "$repo"
    first_file=true
    while IFS= read -r f; do
      rel="${f#"$dir"/}"
      sum=$(shasum -a 256 "$f" | awk '{print $1}')
      $first_file || echo ","
      first_file=false
      printf '    "%s": "%s"' "$rel" "$sum"
    done < <(find "$dir" -type f ! -name '.DS_Store' | LC_ALL=C sort)
    printf '\n  }'
  done
  echo ""
  echo "}"
} > "$OUT"

echo "✓ pinned ${#REPOS[@]} repo(s) → $OUT"

# #163 verify B2: the JSON above is the human-edited source of truth, but the
# binary enforces the *embedded* copy. Without this chain a maintainer could
# re-pin, see the JSON change, commit, and ship a binary still enforcing the old
# digests — with weight-pinning, "I thought I re-pinned" is the whole failure.
# The drift guard in WeightVerifierTests would catch it in CI, but only after
# the maintainer had already believed the re-pin took effect.
"$(cd "$(dirname "$0")" && pwd)/embed-weights-manifest.sh"
