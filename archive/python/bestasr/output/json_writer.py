"""JSON transcript writer.

Named ``json_writer`` (not ``json``) to avoid shadowing the standard library
``json`` module within the package.
"""

from __future__ import annotations

import json

from bestasr.engines.base import Transcript


def to_dict(transcript: Transcript) -> dict:
    """Convert a transcript to a JSON-serializable dict."""
    return {
        "text": transcript.text,
        "language": transcript.language,
        "duration": transcript.duration,
        "backend": transcript.backend,
        "model": transcript.model,
        "segments": [
            {
                "id": seg.id,
                "start": seg.start,
                "end": seg.end,
                "text": seg.text,
                "confidence": seg.confidence,
            }
            for seg in transcript.segments
        ],
    }


def render(transcript: Transcript) -> str:
    """Render the transcript as pretty-printed JSON."""
    return json.dumps(to_dict(transcript), ensure_ascii=False, indent=2)
