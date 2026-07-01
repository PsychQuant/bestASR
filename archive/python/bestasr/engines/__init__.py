"""ASR engine registry.

Exposes the supported backends and helpers to enumerate them and to build the
backend-availability map the router consumes.
"""

from __future__ import annotations

from bestasr.engines.base import (
    BaseEngine,
    Transcript,
    TranscribeOptions,
    TranscriptionError,
    TranscriptSegment,
)
from bestasr.engines.faster_whisper_engine import FasterWhisperEngine
from bestasr.engines.mlx_whisper_engine import MlxWhisperEngine
from bestasr.engines.whisper_cpp_engine import WhisperCppEngine

# Registration order mirrors the router's preference order.
ENGINE_CLASSES: list[type[BaseEngine]] = [
    MlxWhisperEngine,
    FasterWhisperEngine,
    WhisperCppEngine,
]


def get_engines() -> list[BaseEngine]:
    """Instantiate one of each supported engine."""
    return [cls() for cls in ENGINE_CLASSES]


def get_engine(name: str) -> BaseEngine:
    """Return an engine instance by backend name (raises KeyError if unknown)."""
    for engine in get_engines():
        if engine.name == name:
            return engine
    raise KeyError(name)


def availability() -> dict[str, bool]:
    """Return {backend_name: is_available()} for every supported backend."""
    return {engine.name: engine.is_available() for engine in get_engines()}


__all__ = [
    "BaseEngine",
    "Transcript",
    "TranscriptSegment",
    "TranscribeOptions",
    "TranscriptionError",
    "ENGINE_CLASSES",
    "get_engines",
    "get_engine",
    "availability",
]
