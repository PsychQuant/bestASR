"""Static model memory-requirement estimates used by the router.

These are coarse estimates, not measured benchmarks (see design D2). They give
the router a deterministic basis for feasibility and downgrade decisions and are
intentionally centralized here so they can be recalibrated in one place.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ModelRequirements:
    """Estimated memory footprint of a model, in gigabytes.

    ``ram_gb`` applies to CPU-hosted backends; ``vram_gb`` applies to GPU-hosted
    backends. The router selects the relevant figure based on the chosen backend.
    """

    model: str
    ram_gb: float
    vram_gb: float


# (ram_gb, vram_gb) upper-bound estimates for fp16 weights. Quantized/int8
# variants use less, so these are conservative feasibility gates.
_REQUIREMENTS: dict[str, tuple[float, float]] = {
    "tiny": (1.0, 1.0),
    "base": (1.5, 1.5),
    "small": (2.5, 2.5),
    "medium": (5.0, 5.0),
    "large-v3-turbo": (6.0, 6.0),
    "large-v3": (10.0, 10.0),
}


def requirements_for(model: str) -> ModelRequirements:
    """Return the estimated memory requirement for ``model``.

    Raises KeyError for an unknown model — callers pass validated model names.
    """
    ram_gb, vram_gb = _REQUIREMENTS[model]
    return ModelRequirements(model=model, ram_gb=ram_gb, vram_gb=vram_gb)
