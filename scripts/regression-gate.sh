#!/bin/bash
# Regression gate (spec regression-benchmark, #34; design D1/D2/D6).
#
# For the FIXED reference model, transcribe every corpus in
# benchmarks/baseline.json, compute its accuracy metric (CER for zh/ja, WER
# for en — zh is script-normalized per design D7), compare against the pinned
# golden values, and exit non-zero on any regression beyond tolerance.
#
# ACCURACY ONLY: speed (times-realtime) is machine-dependent and is NEVER
# gated (design D1). A gate failure has three possible causes — triage before
# blaming code: code regression, corpus change, or upstream model-artifact
# drift (D7/A3; seeding provenance in benchmarks/baseline-meta.json).
#
# Data-flow discipline (#34 verify): benchmark output and baseline content are
# passed to python as FILES/ARGV/STDIN — never interpolated into python source
# (quoted heredocs only), so hostile or malformed JSON can fail the gate but
# can never execute.
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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/results"

# Work list + reference model from the baseline itself (single fixed canary,
# D2). Validates up front: non-empty baseline, unique corpus names, and
# filesystem-safe names (corpus values flow into paths below).
/usr/bin/python3 - "$BASELINE" > "$TMP/worklist.tsv" <<'PY'
import json, re, sys

entries = json.load(open(sys.argv[1]))
if not entries:
    sys.exit("✗ gate error: baseline is empty — nothing to gate")
seen = set()
for e in entries:
    corpus = e["corpus"]
    if not re.fullmatch(r"[A-Za-z0-9._-]+", corpus) or corpus.startswith("."):
        sys.exit(f"✗ gate error: unsafe corpus name in baseline: {corpus!r}")
    if corpus in seen:
        sys.exit(f"✗ gate error: duplicate corpus in baseline: {corpus}")
    seen.add(corpus)
    print(f"{corpus}\t{e['language']}")
PY

MODEL=$(/usr/bin/python3 - "$BASELINE" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))[0]["model"])
PY
)
echo "regression gate: reference model = whisperkit/$MODEL, baseline = $BASELINE"

# Model-artifact pin verification (#48): the corpora are digest-pinned
# end-to-end; this closes the one remaining link. When baseline-meta carries
# model_files_sha256 the local bundle MUST match — a mismatch is mechanical
# proof of the "third cause" (model drift) and fails the gate BEFORE any
# benchmark spends minutes producing a misleading accuracy diff. Unpinned
# metas warn (TOFU): run scripts/pin-reference-model.sh to pin.
META="${BESTASR_BASELINE_META:-$(dirname "$BASELINE")/baseline-meta.json}"
CACHE_ROOT="${BESTASR_MODEL_CACHE_DIR:-$HOME/Documents/huggingface/models/argmaxinc/whisperkit-coreml}"
MODEL_DIR="$CACHE_ROOT/openai_whisper-$(echo "$MODEL" | sed 's/-\([^-]*\)$/_\1/')"
if [ -f "$META" ]; then
  HAS_PIN=$(/usr/bin/python3 -c "import json,sys; print(1 if json.load(open(sys.argv[1])).get('model_files_sha256') else 0)" "$META")
  if [ "$HAS_PIN" = "1" ]; then
    if [ ! -d "$MODEL_DIR" ]; then
      echo "x gate error: model bundle missing at $MODEL_DIR but baseline-meta pins it" >&2
      echo "  download the reference model, or re-pin via scripts/pin-reference-model.sh" >&2
      exit 1
    fi
    (cd "$MODEL_DIR" && find . -type f ! -name '.*' | sort | while IFS= read -r f; do
      printf '%s\t%s\n' "${f#./}" "$(shasum -a 256 "$f" | cut -d' ' -f1)"
    done) > "$TMP/model-digests.tsv"
    # File, not pipe: `python3 -` reads its script from stdin (heredoc), so a
    # piped data stream would be silently discarded.
    /usr/bin/python3 - "$META" "$TMP/model-digests.tsv" <<'PY'
import json, sys

pinned = json.load(open(sys.argv[1]))["model_files_sha256"]
actual = {}
for line in open(sys.argv[2]):
    line = line.rstrip("\n")
    if line:
        path, digest = line.split("\t")
        actual[path] = digest
problems = []
for path, digest in sorted(pinned.items()):
    if path not in actual:
        problems.append(f"missing from bundle: {path}")
    elif actual[path] != digest:
        problems.append(
            f"drift: {path} (pinned {digest[:12]}..., actual {actual[path][:12]}...)")
extras = sorted(set(actual) - set(pinned))
if problems:
    print("x gate error: reference-model artifacts do not match the pinned digests:",
          file=sys.stderr)
    for p in problems:
        print(f"    {p}", file=sys.stderr)
    print("  This is MECHANICAL proof of model drift (the 'third cause').",
          file=sys.stderr)
    print("  If the upgrade is intentional: re-seed goldens, then re-pin via",
          file=sys.stderr)
    print("  scripts/pin-reference-model.sh.", file=sys.stderr)
    sys.exit(1)
if extras:
    print(f"! note: {len(extras)} file(s) in the bundle are not pinned "
          "(new upstream files?) — consider re-pinning", file=sys.stderr)
print(f"model pin verified: {len(pinned)} files match baseline-meta")
PY
  else
    echo "! warning: baseline-meta has no model_files_sha256 — model drift is only" >&2
    echo "  inferable via revision anchors. Pin it: scripts/pin-reference-model.sh" >&2
  fi
fi

# The standard set on disk must be fully covered by the baseline — a fetched
# standard corpus with no golden would otherwise never be gated (#34 verify).
# User-registered corpora (arbitrary names) are out of scope by pattern.
STANDARD_GAPS=$(cd "$DEST" 2>/dev/null && ls *.wav 2>/dev/null \
  | sed 's/\.wav$//' \
  | grep -E '^(jfk|osr-harvard-[0-9]+|fleurs-ja-[0-9]+|cv-zhtw-[0-9]+)$' \
  | grep -Fxv -f <(cut -f1 "$TMP/worklist.tsv") || true)
if [ -n "$STANDARD_GAPS" ]; then
  echo "✗ gate error: standard corpora on disk with no baseline entry:" >&2
  echo "$STANDARD_GAPS" | sed 's/^/    /' >&2
  echo "  add goldens to benchmarks/baseline.json (never silently skip)" >&2
  exit 1
fi

FAILED_RUNS=0
while IFS=$'\t' read -r corpus language; do
  wav="$DEST/$corpus.wav" srt="$DEST/$corpus.srt"
  if [ ! -f "$wav" ] || [ ! -f "$srt" ]; then
    echo "✗ corpus '$corpus' not on disk ($wav) — run scripts/fetch-corpora.sh first" >&2
    FAILED_RUNS=$((FAILED_RUNS + 1)); continue
  fi
  echo "→ benchmarking $corpus [$language] …"
  # </dev/null: the loop's stdin is the worklist — a benchmark subprocess that
  # reads stdin would silently eat the remaining corpus lines (#34 verify).
  # --decode-deterministic: temperature fallback is stochastic sampling and was
  # observed live to flip a corpus CER between runs — the canary decodes
  # greedy-only so golden comparisons are reproducible (#34 verify).
  if out=$("$BIN" benchmark "$wav" --reference "$srt" --language "$language" \
        --backends whisperkit --models "$MODEL" --decode-deterministic \
        --json </dev/null 2>/dev/null); then
    printf '%s' "$out" > "$TMP/results/$corpus.json"
  else
    echo "✗ benchmark run failed for '$corpus'" >&2
    FAILED_RUNS=$((FAILED_RUNS + 1))
  fi
done < "$TMP/worklist.tsv"

if [ "$FAILED_RUNS" -gt 0 ]; then
  echo "✗ regression gate: $FAILED_RUNS corpus run(s) failed before comparison" >&2
  # 仍執行 compare —— 缺席 corpus 會以 gate error 顯式列出（不靜默）
fi

echo ""
# Assemble {baseline, measured} from the result FILES and pipe into the single
# compare implementation. set -e would kill the script on a failing pipeline
# BEFORE any assignment ran; capture the status through if/else so the
# FAILED_RUNS combination stays explicit.
if /usr/bin/python3 - "$BASELINE" "$TMP/results" <<'PY' | /usr/bin/python3 "$COMPARE"
import json, os, sys

baseline = json.load(open(sys.argv[1]))
results_dir = sys.argv[2]
measured = []
for entry in baseline:
    path = os.path.join(results_dir, entry["corpus"] + ".json")
    if not os.path.exists(path):
        continue  # failed run — compare reports the absence as a gate error
    run = json.load(open(path))
    rows = run.get("results", [])
    if not rows:
        continue
    r = rows[0]
    measured.append({
        "corpus": entry["corpus"],
        "metric": r["metric_kind"],
        "error_rate": r["error_rate"],
    })
json.dump({"baseline": baseline, "measured": measured}, sys.stdout)
PY
then COMPARE_RC=0; else COMPARE_RC=$?; fi
[ "$FAILED_RUNS" -gt 0 ] && exit 1
exit $COMPARE_RC
