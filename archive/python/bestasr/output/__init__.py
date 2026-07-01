"""Transcript output writers and format dispatch.

The default format is ``txt``; an unsupported format raises
``UnsupportedFormatError`` listing the supported set.
"""

from __future__ import annotations

from bestasr.engines.base import Transcript
from bestasr.output import json_writer, srt, txt, vtt

DEFAULT_FORMAT = "txt"

_RENDERERS = {
    "txt": txt.render,
    "json": json_writer.render,
    "srt": srt.render,
    "vtt": vtt.render,
}

SUPPORTED_FORMATS: list[str] = list(_RENDERERS)


class UnsupportedFormatError(ValueError):
    """Raised when an unknown output format is requested."""

    def __init__(self, fmt: str) -> None:
        self.format = fmt
        super().__init__(
            f"unsupported output format: {fmt!r}; "
            f"supported formats are {', '.join(SUPPORTED_FORMATS)}"
        )


def render(transcript: Transcript, fmt: str = DEFAULT_FORMAT) -> str:
    """Render ``transcript`` in ``fmt`` (default ``txt``)."""
    try:
        renderer = _RENDERERS[fmt]
    except KeyError:
        raise UnsupportedFormatError(fmt) from None
    return renderer(transcript)


def write_transcript(
    transcript: Transcript, path: str, fmt: str = DEFAULT_FORMAT
) -> None:
    """Render ``transcript`` in ``fmt`` and write it to ``path`` (UTF-8)."""
    content = render(transcript, fmt)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)
