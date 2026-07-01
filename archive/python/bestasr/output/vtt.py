"""WebVTT transcript writer.

Begins with a ``WEBVTT`` header; timecodes use ``HH:MM:SS.mmm`` (dot separator).
"""

from __future__ import annotations

from bestasr.engines.base import Transcript
from bestasr.output._timecode import format_timestamp


def render(transcript: Transcript) -> str:
    """Render the transcript as WebVTT."""
    cues: list[str] = []
    for seg in transcript.segments:
        start = format_timestamp(seg.start, ".")
        end = format_timestamp(seg.end, ".")
        cues.append(f"{start} --> {end}\n{seg.text}\n")
    body = "\n".join(cues)
    return f"WEBVTT\n\n{body}"
