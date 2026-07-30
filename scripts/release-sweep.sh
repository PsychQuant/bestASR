#!/bin/bash
# Release sweep (#109): the full-matrix deterministic measurement snapshot —
# "under this pinned version, how does EVERY runnable backend×model perform
# on the baseline corpora, on this machine".
#
# For each corpus in benchmarks/baseline.json, runs `bestasr benchmark` with
# NO backend/model filter (the runner enumerates every runnable candidate)
# and --decode-deterministic, so golden-comparable numbers land in the local
# benchmark store with the full condition tuple (app_version / macos_version /
# machine id / hf_revision / quantization). Share the snapshot afterwards with
# `bestasr bench submit` — rows need no special marker; the bench leaderboard
# groups per-version snapshots by the app_version column.
#
# This is NOT a release gate. scripts/release.sh's regression gate (single
# pinned reference model vs goldens) remains the blocker; the sweep is the
# evidence-snapshot regime, run on the reference machine after each release.
#
# Determinism honesty: --decode-deterministic disables the Whisper family's
# stochastic temperature fallback (whisperkit / whisper.cpp). Non-Whisper
# backends (fluid-parakeet / paraformer / sensevoice) decode greedily by
# design; the flag is a no-op there, not a guarantee this script adds.
#
# Usage: scripts/release-sweep.sh [--dry-run] [--backends a,b] [--models x,y]
# Env:   BESTASR_BIN          bestasr binary (default: .build/release/bestasr,
#                             then bestasr on PATH; `swift run` is deliberately
#                             not a fallback — a stale .build makes it rebuild
#                             mid-sweep and fail flakily)
#        BESTASR_CORPORA_DIR  registered corpora (default ~/.bestasr/corpora)
#        BESTASR_BASELINE     baseline.json (default benchmarks/baseline.json)
set -euo pipefail

DRY_RUN=""
BACKENDS=""
MODELS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY_RUN=1 ;;
    --backends) shift; BACKENDS="${1:?--backends needs a value}" ;;
    --models)   shift; MODELS="${1:?--models needs a value}" ;;
    *) echo "✗ unknown argument: $1 (usage: release-sweep.sh [--dry-run] [--backends a,b] [--models x,y])" >&2; exit 2 ;;
  esac
  shift
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${BESTASR_CORPORA_DIR:-$HOME/.bestasr/corpora}"
BASELINE="${BESTASR_BASELINE:-$REPO_ROOT/benchmarks/baseline.json}"
[ -f "$BASELINE" ] || { echo "✗ baseline not found: $BASELINE" >&2; exit 1; }

# Resolve the binary: prebuilt release binary first (fast, no rebuild risk),
# then PATH. No `swift run` fallback — see header.
if [ -n "${BESTASR_BIN:-}" ]; then
  BIN="$BESTASR_BIN"
elif [ -x "$REPO_ROOT/.build/release/bestasr" ]; then
  BIN="$REPO_ROOT/.build/release/bestasr"
elif command -v bestasr >/dev/null 2>&1; then
  BIN="bestasr"
else
  echo "✗ no bestasr binary. Build one first:" >&2
  echo "    swift build -c release --product bestasr" >&2
  echo "  or set BESTASR_BIN=/path/to/bestasr" >&2
  exit 1
fi

# Work list from the baseline (same validation discipline as regression-gate.sh:
# non-empty, unique, filesystem-safe corpus names).
WORKLIST=$(/usr/bin/python3 - "$BASELINE" <<'PY'
import json, re, sys
entries = json.load(open(sys.argv[1]))
if not entries:
    sys.exit("✗ sweep error: baseline is empty — nothing to sweep")
seen = set()
for e in entries:
    corpus = e["corpus"]
    if not re.fullmatch(r"[A-Za-z0-9._-]+", corpus) or corpus.startswith("."):
        sys.exit(f"✗ sweep error: unsafe corpus name in baseline: {corpus!r}")
    if corpus in seen:
        sys.exit(f"✗ sweep error: duplicate corpus in baseline: {corpus}")
    seen.add(corpus)
    print(f"{corpus}\t{e['language']}")
PY
)

TOTAL=$(printf '%s\n' "$WORKLIST" | wc -l | tr -d ' ')
echo "release sweep: $TOTAL corpora × all runnable candidates${BACKENDS:+ (backends: $BACKENDS)}${MODELS:+ (models: $MODELS)}"
echo "  binary:   $BIN"
echo "  corpora:  $DEST"
echo "  baseline: $BASELINE"
echo "  decode:   deterministic (greedy; Whisper-family temperature fallback disabled)"

if [ -n "$DRY_RUN" ]; then
  echo ""
  echo "— dry run: would execute —"
  while IFS=$'\t' read -r corpus language; do
    echo "  $BIN benchmark $DEST/$corpus.wav --reference $DEST/$corpus.srt --language $language --decode-deterministic${BACKENDS:+ --backends $BACKENDS}${MODELS:+ --models $MODELS}"
  done <<< "$WORKLIST"
  echo "— dry run: nothing executed. Candidates are enumerated per corpus by 'bestasr benchmark' (all runnable backend×model rows unless filtered)."
  exit 0
fi

FAILED=0
DONE=0
while IFS=$'\t' read -r corpus language; do
  WAV="$DEST/$corpus.wav"; SRT="$DEST/$corpus.srt"
  if [ ! -f "$WAV" ] || [ ! -f "$SRT" ]; then
    echo "✗ $corpus: missing $WAV or $SRT (run scripts/fetch-corpora.sh) — skipping" >&2
    FAILED=$((FAILED + 1)); continue
  fi
  echo ""
  echo "→ [$((DONE + FAILED + 1))/$TOTAL] $corpus [$language]"
  # </dev/null: the loop's stdin is the worklist — a subprocess reading stdin
  # would silently eat the remaining corpus lines (regression-gate.sh lesson).
  # Corpus-level warn-continue: one broken corpus must not kill the snapshot;
  # per-candidate failures are already warn-continue inside the runner.
  if ! "$BIN" benchmark "$WAV" --reference "$SRT" --language "$language" \
        --decode-deterministic \
        ${BACKENDS:+--backends "$BACKENDS"} ${MODELS:+--models "$MODELS"} \
        </dev/null; then
    echo "✗ benchmark run failed for '$corpus' — continuing with the rest" >&2
    FAILED=$((FAILED + 1)); continue
  fi
  DONE=$((DONE + 1))
done <<< "$WORKLIST"

echo ""
echo "== sweep complete: $DONE/$TOTAL corpora measured${FAILED:+ ($FAILED failed)} =="
echo "Measurements persisted to the local benchmark store with the full version tuple."
echo "Share the snapshot:"
echo "    $BIN bench submit --dry-run    # review what would be submitted"
echo "    $BIN bench submit              # package + open the bench-repo PR"
[ "$FAILED" -gt 0 ] && exit 1
exit 0
