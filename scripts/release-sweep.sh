#!/bin/bash
# Release sweep (#109): the per-version measurement snapshot — "under this
# pinned version, how does each runnable model perform on the CANONICAL
# community corpus, on this machine".
#
# Sweeps every canonical corpus materialized by `bestasr bench pull`
# (~/.bestasr/corpus/audio/<lang>/<name>.wav with reference/<lang>/<name>.txt)
# through `bestasr benchmark --decode-deterministic`. Canonical corpora are the
# ONLY ones `bestasr bench submit` will publish (submission is gated on the
# canonical corpus_id hash), so this — not the local regression-gate set — is
# what makes the snapshot shareable and the bench leaderboard's per-version
# view non-empty.
#
# Coverage honesty: by default `bestasr benchmark` enumerates the runnable
# candidates at priority ceiling 1 — NOT the whole model grid. Lower-priority
# rows (e.g. fluid-paraformer, demoted for a known upstream decode bug, and
# most mlx-audio rows) are excluded by default; pass --all-grid to widen to
# the full grid. The epilogue prints a per-corpus candidate census so a
# partial sweep is visible, never silent.
#
# Determinism honesty: --decode-deterministic disables the Whisper family's
# stochastic temperature fallback (whisperkit / whisper.cpp). Other backends
# (fluid-* and mlx-audio) ignore the flag — their decode is greedy by design
# or out of this flag's reach; the flag is forwarded, not a blanket guarantee.
#
# This is NOT a release gate. scripts/release.sh's regression gate (single
# pinned reference model vs goldens, on its own local corpus set) remains the
# blocker; the sweep is the evidence-snapshot regime, run on the reference
# machine after each release — with a FRESHLY REBUILT binary (see the version
# guard below: measurements stamp app_version from the binary, so a stale
# binary would label the whole snapshot with the previous version).
#
# Usage: scripts/release-sweep.sh [--dry-run] [--all-grid]
#                                 [--backends a,b] [--models x,y]
# Env:   BESTASR_BIN          bestasr binary (default: .build/release/bestasr,
#                             then bestasr on PATH; `swift run` is deliberately
#                             not a fallback — a stale .build makes it rebuild
#                             mid-sweep and fail flakily)
#        BESTASR_CORPUS_DIR   canonical corpus root (default ~/.bestasr/corpus)
#        BESTASR_ALLOW_VERSION_MISMATCH=1   skip the binary-vs-repo version guard
set -euo pipefail

DRY_RUN=""
ALL_GRID=""
BACKENDS=""
MODELS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY_RUN=1 ;;
    --all-grid) ALL_GRID=1 ;;
    --backends) shift; BACKENDS="${1:?--backends needs a value}" ;;
    --models)   shift; MODELS="${1:?--models needs a value}" ;;
    *) echo "✗ unknown argument: $1 (usage: release-sweep.sh [--dry-run] [--all-grid] [--backends a,b] [--models x,y])" >&2; exit 2 ;;
  esac
  shift
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS_ROOT="${BESTASR_CORPUS_DIR:-$HOME/.bestasr/corpus}"

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

# Version guard: measurements stamp app_version from the BINARY, so sweeping
# with a binary older than the checkout would label the whole snapshot with
# the previous version — silently. Compare and refuse on mismatch.
REPO_VERSION=$(sed -nE 's/.*public static let current = "([0-9.]+)".*/\1/p' \
  "$REPO_ROOT/Sources/BestASRKit/Models/DataModels.swift" | head -1)
BIN_VERSION=$("$BIN" --version 2>/dev/null | head -1 | tr -d '[:space:]')
if [ -n "$REPO_VERSION" ] && [ "$BIN_VERSION" != "$REPO_VERSION" ] \
   && [ "${BESTASR_ALLOW_VERSION_MISMATCH:-}" != "1" ]; then
  echo "✗ version guard: binary reports '$BIN_VERSION' but the checkout is '$REPO_VERSION'." >&2
  echo "  A sweep now would stamp every measurement app_version=$BIN_VERSION." >&2
  echo "  Rebuild first:  swift build -c release --product bestasr" >&2
  echo "  (or set BESTASR_ALLOW_VERSION_MISMATCH=1 if the mismatch is intentional)" >&2
  exit 1
fi

# Work list = the canonical corpus materialization (audio/<lang>/<name>.wav ↔
# reference/<lang>/<name>.txt). Only canonical corpora are submittable — the
# regression gate's local set (~/.bestasr/corpora) is deliberately NOT swept.
[ -d "$CORPUS_ROOT/audio" ] || {
  echo "✗ canonical corpus not found at $CORPUS_ROOT/audio" >&2
  echo "  Fetch it first:  $BIN bench pull" >&2
  exit 1
}
WORKLIST=""
MISSING_REF=0
for wav in "$CORPUS_ROOT"/audio/*/*.wav; do
  [ -e "$wav" ] || continue
  lang=$(basename "$(dirname "$wav")")
  name=$(basename "$wav" .wav)
  ref="$CORPUS_ROOT/reference/$lang/$name.txt"
  if [ ! -f "$ref" ]; then
    echo "✗ $name: reference missing ($ref) — skipping" >&2
    MISSING_REF=$((MISSING_REF + 1)); continue
  fi
  WORKLIST="${WORKLIST}${name}\t${lang}\t${wav}\t${ref}\n"
done
WORKLIST=$(printf '%b' "$WORKLIST")
[ -n "$WORKLIST" ] || {
  echo "✗ no canonical corpora with references under $CORPUS_ROOT — run '$BIN bench pull' first" >&2
  exit 1
}

TOTAL=$(printf '%s\n' "$WORKLIST" | wc -l | tr -d ' ')
SCOPE_DESC="priority-1 runnable candidates (default ceiling)"
[ -n "$ALL_GRID" ] && SCOPE_DESC="FULL model grid (--all-grid)"
echo "release sweep: $TOTAL canonical corpora × ${SCOPE_DESC}${BACKENDS:+ (backends: $BACKENDS)}${MODELS:+ (models: $MODELS)}"
echo "  binary:   $BIN (version: ${BIN_VERSION:-unknown})"
echo "  corpus:   $CORPUS_ROOT (canonical — submittable via bench submit)"
echo "  decode:   deterministic flag forwarded (binding for Whisper-family backends only)"
[ "$MISSING_REF" -gt 0 ] && echo "  ⚠ $MISSING_REF corpus(es) skipped: missing reference"

if [ -n "$DRY_RUN" ]; then
  echo ""
  echo "— dry run: would execute —"
  while IFS=$'\t' read -r name lang wav ref; do
    printf '  %q benchmark %q --reference %q --language %q --decode-deterministic%s%s%s --json\n' \
      "$BIN" "$wav" "$ref" "$lang" \
      "${ALL_GRID:+ --all-grid}" \
      "${BACKENDS:+ --backends $BACKENDS}" "${MODELS:+ --models $MODELS}"
  done <<< "$WORKLIST"
  echo "— dry run: nothing executed."
  exit 0
fi

FAILED=0
DONE=0
CENSUS=""
while IFS=$'\t' read -r name lang wav ref; do
  echo ""
  echo "→ [$((DONE + FAILED + 1))/$TOTAL] $name [$lang]"
  # </dev/null: the loop's stdin is the worklist — a subprocess reading stdin
  # would silently eat the remaining corpus lines (regression-gate.sh lesson).
  set +e
  OUT_JSON=$("$BIN" benchmark "$wav" --reference "$ref" --language "$lang" \
        --decode-deterministic \
        ${ALL_GRID:+--all-grid} \
        ${BACKENDS:+--backends "$BACKENDS"} ${MODELS:+--models "$MODELS"} \
        --json </dev/null)
  RC=$?
  set -e
  if [ "$RC" -eq 2 ]; then
    # Usage error (unknown backend/model/flag) is identical for every corpus —
    # fail fast instead of burning the remaining corpora on the same typo.
    echo "✗ usage error from benchmark (exit 2) — aborting the sweep" >&2
    exit 2
  fi
  if [ "$RC" -ne 0 ]; then
    echo "✗ benchmark run failed for '$name' (exit $RC) — continuing with the rest" >&2
    FAILED=$((FAILED + 1)); continue
  fi
  # Candidate census: how many candidates actually produced a measurement —
  # a partial matrix must be visible, never silent.
  read -r N_OK N_FAIL <<< "$(printf '%s' "$OUT_JSON" | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
print(len(d.get("results", [])), len(d.get("failures", [])))')"
  if [ "${N_OK:-0}" -eq 0 ]; then
    echo "✗ $name: 0 candidates measured (${N_FAIL:-0} failed) — counting as failure" >&2
    FAILED=$((FAILED + 1)); continue
  fi
  echo "   ✓ $name: $N_OK candidate(s) measured${N_FAIL:+, $N_FAIL failed}"
  CENSUS="${CENSUS}  ${name} [${lang}]: ${N_OK} measured, ${N_FAIL:-0} candidate-failures\n"
  DONE=$((DONE + 1))
done <<< "$WORKLIST"

echo ""
echo "== sweep complete: $DONE/$TOTAL corpora measured =="
[ "$FAILED" -gt 0 ] && echo "   ⚠ $FAILED corpus run(s) failed — the snapshot is PARTIAL"
echo "— candidate census (visibility for partial matrices) —"
printf '%b' "$CENSUS"
if [ "$DONE" -gt 0 ]; then
  echo "Measurements persisted to the local benchmark store with the full version tuple."
  echo "Share the snapshot:"
  echo "    $BIN bench submit --dry-run    # review what would be submitted"
  echo "    $BIN bench submit              # package + open the bench-repo PR"
fi
[ "$FAILED" -gt 0 ] && exit 1
exit 0
