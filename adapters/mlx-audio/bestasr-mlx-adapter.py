#!/usr/bin/env python3
"""bestASR external-engine adapter for mlx-audio (#51, protocol v1).

Translates the bestASR external-engine protocol to mlx_audio's STT API:

    bestasr-mlx-adapter.py transcribe --audio <path> --model <size>
                           [--language <code>] [--hf-repo <repo>] [--revision <rev>]

stdout on success: one JSON object
    {"protocol": 1, "text": "...", "duration": <seconds>, "segments": [...]?}
failure: non-zero exit with the reason on stderr.

Containment (#20 / design D3): this script runs inside its own venv (see
setup.sh); bestASR only ever sees the protocol JSON. mlx_audio upstream
churn breaks THIS file, never the host.
"""

import argparse
import json
import sys


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    sys.exit(code)


def main() -> None:
    parser = argparse.ArgumentParser(prog="bestasr-mlx-adapter")
    sub = parser.add_subparsers(dest="command", required=True)
    t = sub.add_parser("transcribe")
    t.add_argument("--audio", required=True)
    t.add_argument("--model", required=True)  # grid size — display key only
    t.add_argument("--language", default=None)
    t.add_argument("--hf-repo", default=None)
    t.add_argument("--revision", default=None)
    args = parser.parse_args()

    if not args.hf_repo:
        fail("adapter requires --hf-repo (the grid row carries the pinned repo)")

    try:
        from mlx_audio.stt.utils import load_model  # type: ignore
    except Exception as exc:  # noqa: BLE001 — venv/install problems must be loud
        fail(f"mlx_audio import failed (venv broken or not installed): {exc}")

    repo = args.hf_repo if not args.revision else f"{args.hf_repo}@{args.revision}"
    try:
        model = load_model(args.hf_repo, revision=args.revision)
    except TypeError:
        # Older mlx_audio without a revision kwarg — fall back, revision is
        # then advisory (recorded in the grid, not enforceable here).
        model = load_model(args.hf_repo)
    except Exception as exc:  # noqa: BLE001
        fail(f"model load failed for {repo}: {exc}")

    try:
        kwargs = {}
        if args.language:
            kwargs["language"] = args.language
        result = model.generate(args.audio, **kwargs)
    except TypeError:
        # Some families reject a language kwarg — retry unhinted.
        result = model.generate(args.audio)
    except Exception as exc:  # noqa: BLE001
        fail(f"transcription failed: {exc}")

    text = getattr(result, "text", None)
    if text is None:
        text = str(result)

    duration = 0.0
    segments = None
    raw_segments = getattr(result, "segments", None)
    if raw_segments:
        segments = []
        for seg in raw_segments:
            start = float(getattr(seg, "start", seg.get("start", 0)) if not isinstance(seg, dict) else seg.get("start", 0))
            end = float(getattr(seg, "end", seg.get("end", 0)) if not isinstance(seg, dict) else seg.get("end", 0))
            seg_text = getattr(seg, "text", seg.get("text", "") if isinstance(seg, dict) else "")
            segments.append({"start": start, "end": end, "text": seg_text})
            duration = max(duration, end)
    if duration <= 0:
        try:
            import soundfile  # type: ignore

            info = soundfile.info(args.audio)
            duration = info.frames / info.samplerate
        except Exception:  # noqa: BLE001 — duration stays best-effort
            duration = 0.0

    reply = {"protocol": 1, "text": text, "duration": duration}
    if segments:
        reply["segments"] = segments
    json.dump(reply, sys.stdout, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
