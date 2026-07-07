#!/bin/bash
# Pin the reference model's local CoreML artifacts (#48).
#
# The corpora side of the supply chain is cryptographically pinned end-to-end
# (#34); the reference model was only an audit anchor (repo revision recorded,
# local cache never hashed). This script closes that link: it hashes every
# file in the local model bundle and records the digests in
# benchmarks/baseline-meta.json (model_files_sha256). regression-gate.sh
# verifies them before every run, turning "third-cause" model-drift triage
# from indirect inference into a mechanical check.
#
# Run it when seeding goldens or after an INTENTIONAL model upgrade.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
META="$REPO_ROOT/benchmarks/baseline-meta.json"
[ -f "$META" ] || { echo "x baseline-meta not found: $META" >&2; exit 1; }

MODEL=$(/usr/bin/python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['model'])" "$META")
CACHE_ROOT="${BESTASR_MODEL_CACHE_DIR:-$HOME/Documents/huggingface/models/argmaxinc/whisperkit-coreml}"
# WhisperKit's on-disk folder name: openai_whisper-<model> with the final
# size separator as underscore (large-v3-turbo -> large-v3_turbo).
MODEL_DIR="${1:-$CACHE_ROOT/openai_whisper-$(echo "$MODEL" | sed 's/-\([^-]*\)$/_\1/')}"
[ -d "$MODEL_DIR" ] || {
  echo "x model bundle not found: $MODEL_DIR" >&2
  echo "  download it first (any bestasr transcribe with the reference model)," >&2
  echo "  or pass the bundle directory explicitly: $0 /path/to/bundle" >&2
  exit 1
}

echo "pinning reference model bundle: $MODEL_DIR"
DIGEST_FILE=$(mktemp)
trap 'rm -f "$DIGEST_FILE"' EXIT
(cd "$MODEL_DIR" && find . -type f ! -name '.*' | sort | while IFS= read -r f; do
  printf '%s\t%s\n' "${f#./}" "$(shasum -a 256 "$f" | cut -d' ' -f1)"
done) > "$DIGEST_FILE"
[ -s "$DIGEST_FILE" ] || { echo "x bundle is empty: $MODEL_DIR" >&2; exit 1; }

# NOTE: the digest list rides in a FILE, not the pipe — `python3 -` takes its
# SCRIPT from stdin, so a heredoc would starve a piped data stream (live bug:
# "pinned 0 files").
/usr/bin/python3 - "$META" "$DIGEST_FILE" <<'PY'
import json, sys
from datetime import date

meta = json.load(open(sys.argv[1]))
files = {}
for line in open(sys.argv[2]):
    line = line.rstrip("\n")
    if not line:
        continue
    path, digest = line.split("\t")
    files[path] = digest
meta["model_files_sha256"] = files
meta["model_files_pinned_at"] = date.today().isoformat()
with open(sys.argv[1], "w") as fh:
    json.dump(meta, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(f"pinned {len(files)} files into {sys.argv[1]}")
PY
