#!/bin/bash
# Regression gate (spec regression-benchmark, #34; design D1/D2/D6).
#
# For the FIXED reference model, transcribe every corpus in
# benchmarks/baseline.json, compute its accuracy metric (CER for zh/ja, WER
# for en — zh is script-normalized per design D7), compare against the pinned
# golden values, and exit non-zero on any regression beyond tolerance.
#
# ACCURACY ONLY: speed (times-realtime) is machine-dependent and is NEVER
# gated — this gate is meaningful across machines and in CI (design D1).
# A gate failure has three possible causes — triage before blaming code:
# code regression, corpus change, or upstream model-artifact drift (D7/A3).
#
# Prereqs: corpora registered (scripts/fetch-corpora.sh), reference model
# downloadable/downloaded, /usr/bin/python3 (Xcode CLT).
set -euo pipefail

BIN="${BESTASR_BIN:-bestasr}"
DEST="${BESTASR_CORPORA_DIR:-$HOME/.bestasr/corpora}"
BASELINE="${BESTASR_BASELINE:-$(cd "$(dirname "$0")/.." && pwd)/benchmarks/baseline.json}"
COMPARE="$(cd "$(dirname "$0")" && pwd)/lib/baseline-compare.py"

[ -f "$BASELINE" ] || { echo "✗ baseline not found: $BASELINE" >&2; exit 1; }
[ -f "$COMPARE" ]  || { echo "✗ compare stage missing: $COMPARE" >&2; exit 1; }
/usr/bin/python3 -c "import json" >/dev/null 2>&1 \
  || { echo "✗ working /usr/bin/python3 required (install Xcode CLT)" >&2; exit 1; }

# Reference model comes from the baseline itself (single fixed canary, D2).
MODEL=$(/usr/bin/python3 -c "import json,sys; print(json.load(open('$BASELINE'))[0]['model'])")
echo "regression gate: reference model = whisperkit/$MODEL, baseline = $BASELINE"

MEASURED="[]"
FAILED_RUNS=0
while IFS=$'\t' read -r corpus language; do
  wav="$DEST/$corpus.wav" srt="$DEST/$corpus.srt"
  if [ ! -f "$wav" ] || [ ! -f "$srt" ]; then
    echo "✗ corpus '$corpus' not on disk ($wav) — run scripts/fetch-corpora.sh first" >&2
    FAILED_RUNS=$((FAILED_RUNS + 1)); continue
  fi
  echo "→ benchmarking $corpus [$language] …"
  if ! out=$("$BIN" benchmark "$wav" --reference "$srt" --language "$language" \
        --backends whisperkit --models "$MODEL" --json 2>/dev/null); then
    echo "✗ benchmark run failed for '$corpus'" >&2
    FAILED_RUNS=$((FAILED_RUNS + 1)); continue
  fi
  MEASURED=$(/usr/bin/python3 - "$corpus" <<PY
import json, sys
corpus = sys.argv[1]
run = json.loads('''$out''')
rows = run["results"]
if not rows:
    raise SystemExit(f"no results for {corpus}")
r = rows[0]
acc = json.loads('''$MEASURED''')
acc.append({"corpus": corpus, "metric": r["metric_kind"], "error_rate": r["error_rate"]})
print(json.dumps(acc))
PY
) || { echo "✗ result parse failed for '$corpus'" >&2; FAILED_RUNS=$((FAILED_RUNS + 1)); }
done < <(/usr/bin/python3 -c "
import json
for e in json.load(open('$BASELINE')):
    print(e['corpus'], e['language'], sep='\t')")

if [ "$FAILED_RUNS" -gt 0 ]; then
  echo "✗ regression gate: $FAILED_RUNS corpus run(s) failed before comparison" >&2
  # 仍執行 compare —— 缺席 corpus 會以 gate error 顯式列出（不靜默）
fi

echo ""
# set -e would kill the script on a failing compare BEFORE any assignment ran;
# capture the status through an if so the FAILED_RUNS combination stays explicit.
if /usr/bin/python3 "$COMPARE" <<JSON
{"baseline": $(cat "$BASELINE"), "measured": $MEASURED}
JSON
then COMPARE_RC=0; else COMPARE_RC=$?; fi
[ "$FAILED_RUNS" -gt 0 ] && exit 1
exit $COMPARE_RC
