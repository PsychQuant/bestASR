"""Profile definitions (design D9).

Each profile carries scoring weights (used to document the speed/accuracy
trade-off) and a candidate model list that encodes which model sizes that
profile considers. Model selection picks the most accurate candidate that fits
available memory (see the router).
"""

from __future__ import annotations

DEFAULT_PROFILE = "balanced"

# Weights from the design brief (§7.1). Retained for documentation and for
# labeling; model selection uses the candidate lists below.
PROFILES: dict[str, dict[str, float]] = {
    "fast": {"speed": 0.55, "accuracy": 0.20, "memory_fit": 0.20, "stability": 0.05},
    "balanced": {"speed": 0.35, "accuracy": 0.35, "memory_fit": 0.20, "stability": 0.10},
    "accurate": {"speed": 0.15, "accuracy": 0.60, "memory_fit": 0.15, "stability": 0.10},
}

# Candidate models per profile (design brief §7.4).
PROFILE_MODELS: dict[str, list[str]] = {
    "fast": ["tiny", "base", "small"],
    "balanced": ["small", "medium"],
    "accurate": ["medium", "large-v3-turbo", "large-v3"],
}

PROFILE_NAMES: list[str] = list(PROFILES)


def profile_weights(name: str) -> dict[str, float]:
    """Return the scoring weights for ``name`` (raises ValueError if unknown)."""
    try:
        return PROFILES[name]
    except KeyError:
        raise ValueError(f"unknown profile: {name!r}") from None


def profile_models(name: str) -> list[str]:
    """Return the candidate model list for ``name`` (raises ValueError if unknown)."""
    try:
        return PROFILE_MODELS[name]
    except KeyError:
        raise ValueError(f"unknown profile: {name!r}") from None
