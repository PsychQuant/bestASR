#!/usr/bin/env python3
"""Persistent STT worker for bestASR's mlx-audio backend (#14, design D1).

Run with the dedicated venv python:
    python mlx_worker.py --model <hf_repo>

Protocol (JSON lines):
    stdout after load:  {"ready": true, "model": "<hf_repo>"}
    stdin per request:  {"id": 1, "audio": "/abs/clip.wav", "language": "en"|null}
    stdout per request: {"id": 1, "text": "...", "segments": [{"start": s, "end": e,
                         "text": t}], "language": "..", "error": null}

Per-request errors return an error row and keep the worker alive; only stdin
EOF or a load failure terminates it. stderr is diagnostics, never protocol.
"""

import argparse
import json
import sys


def eprint(*args):
    print(*args, file=sys.stderr, flush=True)


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def load_model(repo: str, **kwargs):
    # mlx_audio.stt exposes load/generate utilities; import inside so a broken
    # install fails before the ready line (the engine treats no-ready as a
    # load failure with the captured stderr). kwargs carry model_type when
    # loading a pinned local snapshot (#15).
    from mlx_audio.stt.utils import load_model as _load  # type: ignore

    return _load(repo, **kwargs)


def segments_from(result):
    rows = []
    for seg in getattr(result, "segments", None) or []:
        try:
            if isinstance(seg, dict):
                rows.append({
                    "start": float(seg.get("start", 0.0)),
                    "end": float(seg.get("end", 0.0)),
                    "text": str(seg.get("text", "")),
                })
            else:
                rows.append({
                    "start": float(getattr(seg, "start", 0.0)),
                    "end": float(getattr(seg, "end", 0.0)),
                    "text": str(getattr(seg, "text", "")),
                })
        except (TypeError, ValueError):
            continue
    return rows or None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--revision", default=None,
                        help="pinned HF revision (commit sha) — supply-chain pin (#15)")
    parser.add_argument("--model-type", default=None,
                        help="model family for type dispatch when loading a pinned "
                             "local snapshot (its dir name is a bare sha)")
    args = parser.parse_args()

    try:
        target = args.model
        kwargs = {}
        if args.revision:
            # Pin the fetch ourselves (#15): mlx_audio's family loaders don't
            # forward `revision`, so snapshot_download resolves the exact
            # pinned commit and load_model gets the immutable local path —
            # loading/inference still go through mlx_audio. The snapshot dir
            # name is a bare sha, so type dispatch needs the explicit
            # model_type kwarg (base_load_model pops it).
            from huggingface_hub import snapshot_download

            target = snapshot_download(args.model, revision=args.revision)
            if args.model_type:
                kwargs["model_type"] = args.model_type.replace("-", "_")
        model = load_model(target, **kwargs)
    except Exception as exc:  # noqa: BLE001 — load failure is fatal by design
        eprint(f"mlx_worker: model load failed: {exc}")
        return 1

    emit({"ready": True, "model": args.model})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            emit({"id": -1, "text": None, "segments": None, "language": None,
                  "error": f"bad request json: {exc}"})
            continue
        req_id = request.get("id", -1)
        try:
            kwargs = {}
            if request.get("language"):
                kwargs["language"] = request["language"]
            result = model.generate(request["audio"], **kwargs)
            emit({
                "id": req_id,
                "text": str(getattr(result, "text", "") or ""),
                "segments": segments_from(result),
                "language": getattr(result, "language", None) or request.get("language"),
                "error": None,
            })
        except Exception as exc:  # noqa: BLE001 — per-request errors stay non-fatal
            emit({"id": req_id, "text": None, "segments": None, "language": None,
                  "error": str(exc)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
