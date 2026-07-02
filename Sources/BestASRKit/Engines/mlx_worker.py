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


def load_model(repo: str):
    # mlx_audio.stt exposes load/generate utilities; import inside so a broken
    # install fails before the ready line (the engine treats no-ready as a
    # load failure with the captured stderr).
    from mlx_audio.stt.utils import load_model as _load  # type: ignore

    return _load(repo)


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
    args = parser.parse_args()

    try:
        model = load_model(args.model)
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
