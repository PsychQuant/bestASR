"""ffmpeg / ffprobe helpers.

ffmpeg is an external tool, never a hard dependency. These helpers report its
presence and probe audio metadata, degrading gracefully when it is absent.
"""

from __future__ import annotations

import json
import shutil
import subprocess


def has_ffmpeg() -> bool:
    """True if an ``ffmpeg`` executable is resolvable on PATH."""
    return shutil.which("ffmpeg") is not None


def has_ffprobe() -> bool:
    """True if an ``ffprobe`` executable is resolvable on PATH."""
    return shutil.which("ffprobe") is not None


def ffprobe_audio(path: str) -> dict | None:
    """Return ffprobe's parsed JSON for ``path``, or None if probing fails.

    Never raises for the common failure modes (missing ffprobe, unreadable
    file, malformed output) — callers fall back to lower-fidelity probing.
    """
    if not has_ffprobe():
        return None
    cmd = [
        "ffprobe",
        "-v",
        "quiet",
        "-print_format",
        "json",
        "-show_format",
        "-show_streams",
        path,
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
