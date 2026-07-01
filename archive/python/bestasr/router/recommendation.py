"""``ASRRecommendation`` and the ``recommend`` orchestrator.

``recommend`` wires backend selection, model selection with memory downgrade,
and compute-type choice into a single explainable recommendation. It never
touches an engine directly — callers pass a backend-availability map (see
``select_backend``); when omitted, all supported backends are assumed available.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from bestasr.models.registry import SUPPORTED_MODELS, accuracy_label, speed_label
from bestasr.router.profiles import DEFAULT_PROFILE
from bestasr.router.rules import SUPPORTED_BACKENDS, select_backend
from bestasr.router.scorer import (
    available_memory,
    ensure_fits,
    select_compute_type,
    select_model,
)


@dataclass(frozen=True)
class ASRRecommendation:
    """A chosen backend/model/compute-type plus the reasoning behind it."""

    backend: str
    model: str
    compute_type: str
    profile: str
    language: str | None
    estimated_speed: str
    estimated_accuracy: str
    reason: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def default_availability() -> dict[str, bool]:
    """Assume every supported backend is available (callers override with reality)."""
    return {backend: True for backend in SUPPORTED_BACKENDS}


def to_dict(recommendation: "ASRRecommendation") -> dict:
    """Convert a recommendation to a JSON-serializable dict (for ``recommend``)."""
    return {
        "backend": recommendation.backend,
        "model": recommendation.model,
        "compute_type": recommendation.compute_type,
        "profile": recommendation.profile,
        "language": recommendation.language,
        "estimated_speed": recommendation.estimated_speed,
        "estimated_accuracy": recommendation.estimated_accuracy,
        "reason": list(recommendation.reason),
        "warnings": list(recommendation.warnings),
    }


def recommend(
    system,
    audio=None,
    profile: str = DEFAULT_PROFILE,
    backend_override: str | None = None,
    model_override: str | None = None,
    available: dict[str, bool] | None = None,
) -> ASRRecommendation:
    """Produce an explainable recommendation for ``system``/``audio``.

    Raises ``NoBackendAvailableError`` when no backend is available and
    ``ValueError`` for an unknown explicit model.
    """
    if model_override is not None and model_override not in SUPPORTED_MODELS:
        raise ValueError(f"unknown model: {model_override!r}")

    availability = available if available is not None else default_availability()

    reasons: list[str] = []
    warnings: list[str] = []

    backend, b_reasons, b_warnings = select_backend(system, availability, backend_override)
    reasons += b_reasons
    warnings += b_warnings

    avail_mem = available_memory(system, backend)

    if model_override is not None:
        reasons.append(f"model '{model_override}' explicitly requested")
        model, d_warnings, d_reasons = ensure_fits(model_override, avail_mem, backend)
        reasons += d_reasons
        warnings += d_warnings
    else:
        model, m_reasons, m_warnings = select_model(profile, avail_mem, backend)
        reasons += m_reasons
        warnings += m_warnings

    compute_type = select_compute_type(backend, system)
    reasons.append(f"compute type '{compute_type}' chosen for {backend}")

    language = audio.language if audio is not None else None

    return ASRRecommendation(
        backend=backend,
        model=model,
        compute_type=compute_type,
        profile=profile,
        language=language,
        estimated_speed=speed_label(model),
        estimated_accuracy=accuracy_label(model),
        reason=reasons,
        warnings=warnings,
    )
