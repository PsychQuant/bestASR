"""``AudioInfo`` and audio probing (design D8).

Probing prefers ffprobe; when ffmpeg/ffprobe is absent it degrades to
extension-based inference and records a note for the caller (requirement:
graceful degradation when a probe tool is unavailable).
"""

from __future__ import annotations

import os
from dataclasses import dataclass

from bestasr.detect.language import resolve_language
from bestasr.utils.ffmpeg import ffprobe_audio, has_ffprobe


@dataclass(frozen=True)
class AudioInfo:
    """Properties of an audio file used by the router and engines."""

    path: str
    duration: float | None = None
    format: str | None = None
    sample_rate: int | None = None
    channels: int | None = None
    language: str | None = None


def _note(notes: list[str] | None, message: str) -> None:
    if notes is not None:
        notes.append(message)


def _extension_format(path: str) -> str | None:
    ext = os.path.splitext(path)[1].lstrip(".").lower()
    return ext or None


def _parse_ffprobe(data: dict) -> tuple[float | None, str | None, int | None, int | None]:
    fmt = data.get("format", {})
    duration = None
    raw_duration = fmt.get("duration")
    if raw_duration is not None:
        try:
            duration = float(raw_duration)
        except (TypeError, ValueError):
            duration = None
    format_name = fmt.get("format_name")
    if isinstance(format_name, str) and format_name:
        format_name = format_name.split(",")[0]
    else:
        format_name = None

    sample_rate = None
    channels = None
    for stream in data.get("streams", []):
        if stream.get("codec_type") == "audio":
            sr = stream.get("sample_rate")
            if sr is not None:
                try:
                    sample_rate = int(sr)
                except (TypeError, ValueError):
                    sample_rate = None
            ch = stream.get("channels")
            if isinstance(ch, int):
                channels = ch
            break
    return duration, format_name, sample_rate, channels


def probe_audio(
    path: str,
    requested_language: str | None = None,
    notes: list[str] | None = None,
) -> AudioInfo:
    """Probe ``path`` for duration/format/sample_rate/channels and resolve language.

    Uses ffprobe when available; otherwise infers the format from the file
    extension and records a degradation note.
    """
    language = resolve_language(requested_language)

    data = ffprobe_audio(path) if has_ffprobe() else None
    if data is not None:
        duration, fmt, sample_rate, channels = _parse_ffprobe(data)
        if fmt is None:
            fmt = _extension_format(path)
        return AudioInfo(
            path=path,
            duration=duration,
            format=fmt,
            sample_rate=sample_rate,
            channels=channels,
            language=language,
        )

    _note(
        notes,
        "ffmpeg/ffprobe unavailable; audio metadata limited to file extension",
    )
    return AudioInfo(
        path=path,
        duration=None,
        format=_extension_format(path),
        sample_rate=None,
        channels=None,
        language=language,
    )
