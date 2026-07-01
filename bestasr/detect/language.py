"""Transcription-language resolution (design D8).

An explicit language is used verbatim; ``auto`` (or an empty request) defers
detection to the engine and is represented as ``None``.
"""

from __future__ import annotations


def resolve_language(requested: str | None) -> str | None:
    """Return the effective language, or None when detection is deferred."""
    if requested is None:
        return None
    normalized = requested.strip().lower()
    if normalized in ("", "auto"):
        return None
    return normalized
