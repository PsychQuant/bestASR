"""Shared subtitle timecode formatting."""

from __future__ import annotations


def format_timestamp(seconds: float, millis_sep: str) -> str:
    """Format ``seconds`` as ``HH:MM:SS<sep>mmm`` (SRT uses ',', VTT uses '.')."""
    total_ms = round(max(0.0, seconds) * 1000)
    hours = total_ms // 3_600_000
    minutes = (total_ms % 3_600_000) // 60_000
    secs = (total_ms % 60_000) // 1000
    millis = total_ms % 1000
    return f"{hours:02d}:{minutes:02d}:{secs:02d}{millis_sep}{millis:03d}"
