"""SubRip (SRT) transcript writer.

Timecodes use ``HH:MM:SS,mmm`` (comma separator) and 1-based sequential indices.
"""

from __future__ import annotations

from bestasr.engines.base import Transcript
from bestasr.output._timecode import format_timestamp


def render(transcript: Transcript) -> str:
    """Render the transcript as SRT cues."""
    cues: list[str] = []
    for index, seg in enumerate(transcript.segments, start=1):
        start = format_timestamp(seg.start, ",")
        end = format_timestamp(seg.end, ",")
        cues.append(f"{index}\n{start} --> {end}\n{seg.text}\n")
    return "\n".join(cues)
