"""Model selection, memory-fit downgrade (design D4), and compute-type choice (D5).

Selection uses the profile's candidate list and picks the most accurate model
whose estimated requirement fits available memory; when none fit, it downgrades
along the chain, recording a warning per step.
"""

from __future__ import annotations

from bestasr.models.registry import accuracy_of, next_smaller
from bestasr.models.requirements import requirements_for
from bestasr.router.profiles import profile_models


def available_memory(system, backend: str) -> float:
    """Return the memory pool (GB) that constrains model choice for ``backend``."""
    if backend == "faster-whisper":
        # GPU-hosted: VRAM constrains. Fall back to RAM if VRAM is unknown.
        return system.vram_gb if system.vram_gb is not None else system.ram_gb
    # mlx-whisper (unified memory) and whisper.cpp (system RAM).
    return system.ram_gb


def _need(model: str, backend: str) -> float:
    req = requirements_for(model)
    return req.vram_gb if backend == "faster-whisper" else req.ram_gb


def _fits(model: str, avail_mem: float, backend: str) -> bool:
    return _need(model, backend) <= avail_mem


def ensure_fits(
    model: str, avail_mem: float, backend: str
) -> tuple[str, list[str], list[str]]:
    """Downgrade ``model`` until it fits ``avail_mem``; return (model, warnings, reasons)."""
    warnings: list[str] = []
    reasons: list[str] = []
    current = model
    while not _fits(current, avail_mem, backend):
        nxt = next_smaller(current)
        if nxt is None:
            warnings.append(
                f"even '{current}' may not fit ~{avail_mem:g} GB available; using it anyway"
            )
            break
        warnings.append(
            f"'{current}' needs ~{_need(current, backend):g} GB but only "
            f"~{avail_mem:g} GB available; downgrading to '{nxt}'"
        )
        reasons.append(f"downgraded '{current}' to '{nxt}' to fit memory")
        current = nxt
    return current, warnings, reasons


def select_model(
    profile: str, avail_mem: float, backend: str
) -> tuple[str, list[str], list[str]]:
    """Pick the most accurate profile candidate that fits, else downgrade below it."""
    reasons: list[str] = []
    warnings: list[str] = []
    candidates = profile_models(profile)
    feasible = [m for m in candidates if _fits(m, avail_mem, backend)]
    if feasible:
        chosen = max(feasible, key=accuracy_of)
        reasons.append(f"{profile} profile selected '{chosen}'")
        return chosen, reasons, warnings

    smallest = min(candidates, key=accuracy_of)
    reasons.append(
        f"no '{profile}' profile model fits ~{avail_mem:g} GB; starting from '{smallest}'"
    )
    chosen, dwarnings, dreasons = ensure_fits(smallest, avail_mem, backend)
    return chosen, reasons + dreasons, warnings + dwarnings


def select_compute_type(backend: str, system) -> str:
    """Choose the compute type for ``backend`` given available memory (design D5)."""
    if backend == "mlx-whisper":
        return "fp16"
    if backend == "faster-whisper":
        if system.vram_gb is not None and system.vram_gb >= 8:
            return "fp16"
        return "int8_float16"
    return "int8"  # whisper.cpp — quantized/int8
