#!/usr/bin/env python3
"""Emit docs/model-identity-audit.csv — every reachable model version, with the
completeness of its identity made explicit.

Written for issue #183 discuss. Reads the registered catalog
(``~/.bestasr/store/models.jsonl``) rather than parsing Swift, because that file
already carries the upstream fields (``hf_repo`` / ``hf_revision`` / ``verified``)
that the catalog literals feed.

The point of the audit is the ``placeholder_*`` columns: ``default`` currently
stands for four different facts, and this is where you can see which is which.
"""

import csv
import json
import os
import sys

STORE = os.path.expanduser("~/.bestasr/store/models.jsonl")
OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "model-identity-audit.csv")

# Why each `default` is there. Evidence gathered in the #183 discuss:
#   - fluid-*      : ChineseFamilyEngine calls ParaformerManager.load() /
#                    SenseVoiceManager.load() with NO precision argument, while
#                    FluidAudio ships ParakeetEncoderPrecision {int8, int4}.
#                    So the value is whatever the dependency picks — and it can
#                    change on a version bump without the identity changing.
#   - whisperkit   : ModelRegistry comment "CoreML bundles published per-variant
#                    (default = standard build)"; WhisperKit fetches its own
#                    weights, so no hf_repo is recorded here.
#   - apple-speech : OS-bundled. Quantization is not a dimension at all.
#   - mlx-audio    : per-row; some pinned repos carry the real quant in the id
#                    (Mediform/canary-1b-v2-mlx-q8), others are unverified.
REASON = {
    "fluid-parakeet": ("dependency-decides", "FluidAudio picks precision; load() called without it"),
    "fluid-paraformer": ("dependency-decides", "FluidAudio picks precision; load() called without it"),
    "fluid-sensevoice": ("dependency-decides", "FluidAudio picks precision; load() called without it"),
    "whisperkit": ("runtime-decides", "WhisperKit fetches its own bundle; 'default' = standard build"),
    "apple-speech": ("not-applicable", "OS-bundled; no quantization dimension, version tracks macOS"),
}


def classify(row):
    """Return (identity_complete, placeholder_field, kind, meaning)."""
    backend, size, quant = row["backend"], row["size"], row["quantization"]
    size_ph = size == "default"
    quant_ph = quant == "default"
    if not size_ph and not quant_ph:
        return "yes", "", "", ""

    field = "size+quantization" if size_ph and quant_ph else ("size" if size_ph else "quantization")

    if size_ph:
        # No published size at all — the identity names only a family.
        return "no", field, "upstream-unpublished", "upstream publishes no size; identity is family-only"

    kind, meaning = REASON.get(backend, (None, None))
    if kind:
        return "no", field, kind, meaning

    # mlx-audio: the pinned repo id sometimes carries the real quantization.
    repo = row.get("hf_repo") or ""
    for token in ("q8", "q4", "4bit", "8bit", "int8", "int4", "fp16", "bf16"):
        if token in repo.lower():
            return ("no", field, "recoverable-from-repo-id",
                    f"pinned repo id states the quantization: {token}")
    if row.get("verified"):
        return "no", field, "pinned-but-unstated", "repo+revision pinned, quantization not written down"
    return "no", field, "unknown", "no verified repo; quantization genuinely unknown"


def main():
    if not os.path.exists(STORE):
        sys.exit(f"store not found: {STORE}")
    rows = [json.loads(line) for line in open(STORE) if line.strip()]

    fields = [
        "model_id", "runtime", "family", "size", "quantization",
        "identity_complete", "placeholder_field", "placeholder_kind", "placeholder_meaning",
        "hf_repo", "hf_revision", "verified", "est_memory_gb", "priority", "languages",
    ]
    out_rows = []
    for r in sorted(rows, key=lambda x: (x["backend"], x["family"], x["size"], x["quantization"])):
        complete, field, kind, meaning = classify(r)
        out_rows.append({
            "model_id": r["model_id"],
            "runtime": r["backend"],
            "family": r["family"],
            "size": r["size"],
            "quantization": r["quantization"],
            "identity_complete": complete,
            "placeholder_field": field,
            "placeholder_kind": kind,
            "placeholder_meaning": meaning,
            "hf_repo": r.get("hf_repo") or "",
            "hf_revision": r.get("hf_revision") or "",
            "verified": r.get("verified"),
            "est_memory_gb": r.get("est_memory_gb"),
            "priority": r.get("priority"),
            "languages": "/".join(r.get("languages") or []),
        })

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(out_rows)

    n = len(out_rows)
    bad = sum(1 for r in out_rows if r["identity_complete"] == "no")
    print(f"wrote {os.path.normpath(OUT)}: {n} rows, {bad} with an incomplete identity")
    kinds = {}
    for r in out_rows:
        if r["placeholder_kind"]:
            kinds[r["placeholder_kind"]] = kinds.get(r["placeholder_kind"], 0) + 1
    for k, v in sorted(kinds.items(), key=lambda kv: -kv[1]):
        print(f"  {k:26s} {v}")


if __name__ == "__main__":
    main()
