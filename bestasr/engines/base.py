"""Engine-facing data structures and the common ``BaseEngine`` interface.

Every backend implements the same interface (design D6): availability is probed
via lazy import and reported as a boolean, transcription returns a normalized
``Transcript``, and requirement estimation shares the static model table.
"""

from __future__ import annotations

import importlib.util
from abc import ABC, abstractmethod
from dataclasses import dataclass, field

from bestasr.models.requirements import ModelRequirements, requirements_for


@dataclass(frozen=True)
class TranscriptSegment:
    """A single timed span of transcribed text."""

    id: int
    start: float
    end: float
    text: str
    confidence: float | None = None


@dataclass(frozen=True)
class Transcript:
    """A normalized transcription result, independent of the backend used."""

    text: str
    language: str | None
    duration: float | None
    backend: str
    model: str
    segments: list[TranscriptSegment] = field(default_factory=list)


@dataclass(frozen=True)
class TranscribeOptions:
    """Resolved parameters handed to an engine's ``transcribe`` method."""

    model: str
    compute_type: str
    language: str | None = None


class TranscriptionError(RuntimeError):
    """Raised when a backend cannot produce a transcript."""


def module_available(name: str) -> bool:
    """True if ``name`` is importable; False on any probe failure (never raises)."""
    try:
        return importlib.util.find_spec(name) is not None
    except Exception:  # noqa: BLE001 - a broken/partial install counts as unavailable
        return False


def build_transcript(
    raw_segments: list[dict],
    language: str | None,
    backend: str,
    model: str,
    duration: float | None = None,
) -> Transcript:
    """Normalize raw backend segments into a ``Transcript``.

    Segments are ordered by start time and given 1-based ids; the full text is
    the concatenation of segment texts; duration defaults to the last segment's
    end when not provided.
    """
    ordered = sorted(raw_segments, key=lambda s: s["start"])
    segments = [
        TranscriptSegment(
            id=index,
            start=float(seg["start"]),
            end=float(seg["end"]),
            text=seg["text"],
            confidence=seg.get("confidence"),
        )
        for index, seg in enumerate(ordered, start=1)
    ]
    text = "".join(seg.text for seg in segments).strip()
    if duration is None and segments:
        duration = segments[-1].end
    return Transcript(
        text=text,
        language=language,
        duration=duration,
        backend=backend,
        model=model,
        segments=segments,
    )


class BaseEngine(ABC):
    """Common interface every ASR backend implements (design D6).

    ``transcribe`` is a template method: it delegates the backend-specific work
    to ``_transcribe_raw`` and normalizes the result, wrapping any failure in a
    ``TranscriptionError`` so callers see a consistent, typed error.
    """

    name: str = "base"

    @abstractmethod
    def is_available(self) -> bool:
        """Return whether this backend's runtime is usable on the host."""

    @abstractmethod
    def _transcribe_raw(
        self, audio_path: str, options: TranscribeOptions
    ) -> tuple[list[dict], str | None, float | None]:
        """Run the backend and return (raw_segments, language, duration)."""

    def transcribe(self, audio_path: str, options: TranscribeOptions) -> Transcript:
        """Transcribe ``audio_path`` and return a normalized ``Transcript``."""
        try:
            raw, language, duration = self._transcribe_raw(audio_path, options)
        except TranscriptionError:
            raise
        except Exception as exc:  # noqa: BLE001 - normalize every backend failure
            raise TranscriptionError(
                f"{self.name} failed to transcribe {audio_path!r}: {exc}"
            ) from exc
        resolved_language = language if language is not None else options.language
        return build_transcript(raw, resolved_language, self.name, options.model, duration)

    def estimate_requirements(self, model_name: str) -> ModelRequirements:
        """Return the estimated memory requirement for ``model_name``."""
        return requirements_for(model_name)
