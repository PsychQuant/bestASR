"""Plain-text transcript writer."""

from __future__ import annotations

from bestasr.engines.base import Transcript


def render(transcript: Transcript) -> str:
    """Render the transcript as its plain text."""
    return transcript.text
