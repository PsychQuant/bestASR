"""Catalog of supported ASR models and their coarse characteristics.

Accuracy/speed are normalized 0..1 estimates (not measured benchmarks, see
design D2) used by the router to pick within a profile's candidate list and to
label a recommendation's estimated speed/accuracy.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ModelSpec:
    name: str
    accuracy: float  # 0..1, higher is more accurate
    speed: float  # 0..1, higher is faster


MODEL_SPECS: dict[str, ModelSpec] = {
    "tiny": ModelSpec("tiny", accuracy=0.20, speed=1.00),
    "base": ModelSpec("base", accuracy=0.35, speed=0.90),
    "small": ModelSpec("small", accuracy=0.50, speed=0.75),
    "medium": ModelSpec("medium", accuracy=0.70, speed=0.55),
    "large-v3-turbo": ModelSpec("large-v3-turbo", accuracy=0.85, speed=0.60),
    "large-v3": ModelSpec("large-v3", accuracy=1.00, speed=0.35),
}

SUPPORTED_MODELS: list[str] = list(MODEL_SPECS)

# Memory-downgrade order, largest first (design D4). large-v3-turbo is a large-
# tier model whose downgrade successor is medium (see ``next_smaller``).
DOWNGRADE_CHAIN: list[str] = ["large-v3", "medium", "small", "base", "tiny"]


def accuracy_of(model: str) -> float:
    return MODEL_SPECS[model].accuracy


def speed_of(model: str) -> float:
    return MODEL_SPECS[model].speed


def next_smaller(model: str) -> str | None:
    """Return the next smaller model in the downgrade chain, or None at the end."""
    if model == "large-v3-turbo":
        return "medium"
    if model in DOWNGRADE_CHAIN:
        idx = DOWNGRADE_CHAIN.index(model)
        if idx + 1 < len(DOWNGRADE_CHAIN):
            return DOWNGRADE_CHAIN[idx + 1]
    return None


def _label(value: float, high: float, mid: float, names: tuple[str, str, str]) -> str:
    if value >= high:
        return names[0]
    if value >= mid:
        return names[1]
    return names[2]


def speed_label(model: str) -> str:
    return _label(speed_of(model), 0.70, 0.45, ("fast", "medium", "slow"))


def accuracy_label(model: str) -> str:
    return _label(accuracy_of(model), 0.70, 0.45, ("high", "medium", "low"))
