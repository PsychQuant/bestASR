#!/usr/bin/env bash
# Non-vacuousness check for the regression gate's guards (#134).
#
# Deletes each guard in scripts/lib/baseline-compare.py (and one in
# scripts/regression-gate.sh) independently, re-runs RegressionBaselineTests,
# and prints how many assertions each deletion breaks. A guard that scores 0 is
# indistinguishable from its absence — the compare script's own words for that
# are "not a guard, it is a comment with syntax", and #134 exists because the
# gate's reassuring output had outrun what it could actually prove.
#
# The counts in CHANGELOG.md and in PR #140 come from this script. It is
# committed so a reader holding only the diff can re-run the claim rather than
# trust it, which is the same standard the change asks of the gate's own log.
#
#   ./scripts/mutation-check.sh
#
# Mutation is done on COPIES; the working tree is restored and verified after
# every case. Requires a clean tree (the guards are patched in place while a
# case runs, so an unrelated edit would be reverted along with the mutation).
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain scripts/lib/baseline-compare.py scripts/regression-gate.sh)" ]; then
  echo "✗ refusing to run: baseline-compare.py or regression-gate.sh has uncommitted changes." >&2
  echo "  This script patches them in place and restores from its own backup;" >&2
  echo "  running it over unsaved work would be indistinguishable from losing it." >&2
  exit 1
fi

COMPARE=scripts/lib/baseline-compare.py
GATE=scripts/regression-gate.sh
BACKUP=$(mktemp -d)
trap 'cp "$BACKUP/compare" "$COMPARE"; cp "$BACKUP/gate" "$GATE"; rm -rf "$BACKUP"' EXIT
cp "$COMPARE" "$BACKUP/compare"
cp "$GATE" "$BACKUP/gate"

# Build once so each case is a test run, not a rebuild.
swift build --build-tests >/dev/null 2>&1

count() {
  swift test --skip-build --filter RegressionBaselineTests 2>&1 | grep -c 'recorded an issue' || true
}

restore() { cp "$BACKUP/compare" "$COMPARE"; cp "$BACKUP/gate" "$GATE"; }

printf '%-34s %s\n' "guard deleted" "assertions broken"
printf '%-34s %s\n' "----------------------------------" "-----------------"
printf '%-34s %s\n' "(none — control)" "$(count)"

# file:sed-expression:label
CASES=(
  "$COMPARE:s/^EFFECTIVE_THRESHOLD_MAX = 0.5/EFFECTIVE_THRESHOLD_MAX = float(\"inf\")/:effective-threshold sum bound"
  "$COMPARE:s/^    expected = data.get(\"expected_corpora\")/    expected = None/:completeness anchor"
  "$COMPARE:s/if not math.isfinite(number):/if False:/:isfinite"
  "$COMPARE:s/    if isinstance(value, bool):/    if False:/:boolean guard"
  "$COMPARE:s/^TOLERANCE_MAX = 0.25/TOLERANCE_MAX = float(\"inf\")/:TOLERANCE_MAX"
  "$COMPARE:s/except (TypeError, ValueError, OverflowError):/except (TypeError, ValueError):/:OverflowError"
  "$COMPARE:s/^ERROR_RATE_MAX = 100.0/ERROR_RATE_MAX = float(\"inf\")/:ERROR_RATE_MAX"
  "$COMPARE:s/^_MAX_ECHO = 120/_MAX_ECHO = 10**9/:echo cap"
  "$GATE:s/\.get(\"corpora\")\$/.get(\"corpora_SET\")/:gate anchor wiring"
)

FAILED=0
for case in "${CASES[@]}"; do
  file="${case%%:*}"; rest="${case#*:}"
  expr="${rest%:*}"; label="${rest##*:}"
  sed -i '' "$expr" "$file"
  if ! git diff --quiet "$file"; then
    n=$(count)
  else
    n="PATTERN NOT FOUND"   # the guard moved; the mutation silently applied to nothing
    FAILED=1
  fi
  printf '%-34s %s\n' "$label" "$n"
  [ "$n" = "0" ] && FAILED=1
  restore
done

echo
if [ -n "$(git status --porcelain "$COMPARE" "$GATE")" ]; then
  echo "✗ working tree not restored — inspect before continuing." >&2
  exit 1
fi
echo "✓ working tree restored."
if [ "$FAILED" = "1" ]; then
  echo "✗ a guard scored 0, or a mutation pattern no longer matches." >&2
  echo "  Either the guard is inert and should be deleted rather than kept," >&2
  echo "  or it needs a test that can tell it from its absence." >&2
  exit 1
fi
echo "✓ every guard is load-bearing."
