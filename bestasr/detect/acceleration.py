"""Acceleration-backend availability probes (CUDA / Metal / MLX).

Each probe attempts an import or a platform query and returns a boolean. Any
exception is treated as "unavailable" rather than propagated (design D6), so a
machine missing a backend degrades cleanly instead of crashing.
"""

from __future__ import annotations

import importlib.util
import platform
import shutil


def _safe_bool(fn) -> bool:
    try:
        return bool(fn())
    except Exception:  # noqa: BLE001 - any probe failure means "unavailable"
        return False


def _can_import(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


def has_cuda() -> bool:
    """True if an NVIDIA CUDA GPU appears usable (nvidia-smi present)."""
    return _safe_bool(lambda: shutil.which("nvidia-smi") is not None)


def has_metal() -> bool:
    """True on macOS, where Metal is available to supported backends."""
    return _safe_bool(lambda: platform.system() == "Darwin")


def has_mlx() -> bool:
    """True on Apple Silicon with the mlx runtime importable."""

    def _probe() -> bool:
        if platform.system() != "Darwin" or platform.machine() != "arm64":
            return False
        return _can_import("mlx_whisper") or _can_import("mlx")

    return _safe_bool(_probe)
