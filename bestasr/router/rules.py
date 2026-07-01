"""Backend selection decision table (design D2/D3) with explicit-override fallback.

The router never probes engines directly; the caller passes an ``available``
map (backend name -> bool) built from engine ``is_available()`` checks. This
keeps the routing layer decoupled from any backend (design D6) and fully
testable with fabricated availability.
"""

from __future__ import annotations

SUPPORTED_BACKENDS: list[str] = ["mlx-whisper", "faster-whisper", "whisper.cpp"]

_INSTALL_HINTS = {
    "mlx-whisper": "pip install mlx-whisper (Apple Silicon)",
    "faster-whisper": "pip install faster-whisper (CUDA/CPU)",
    "whisper.cpp": "install a whisper.cpp binding, e.g. pip install pywhispercpp",
}


class NoBackendAvailableError(RuntimeError):
    """Raised when no supported backend reports availability."""

    def __init__(self, backends: list[str]) -> None:
        self.backends = list(backends)
        hints = "; ".join(_INSTALL_HINTS[b] for b in backends if b in _INSTALL_HINTS)
        super().__init__(
            "No ASR backend is available. Install one of: "
            f"{', '.join(backends)}. Try: {hints}."
        )


def select_backend(
    system,
    available: dict[str, bool],
    override: str | None = None,
) -> tuple[str, list[str], list[str]]:
    """Choose a backend, returning (backend, reasons, warnings).

    Raises ``NoBackendAvailableError`` when nothing is available.
    """
    reasons: list[str] = []
    warnings: list[str] = []

    def is_avail(backend: str) -> bool:
        return bool(available.get(backend, False))

    if override is not None:
        if is_avail(override):
            reasons.append(f"backend '{override}' explicitly requested")
            return override, reasons, warnings
        warnings.append(
            f"requested backend '{override}' is unavailable; selecting automatically"
        )

    if system.has_mlx and is_avail("mlx-whisper"):
        reasons.append("Apple Silicon with MLX available")
        reasons.append("MLX is recommended for local ASR on Apple Silicon")
        return "mlx-whisper", reasons, warnings

    if system.has_cuda and is_avail("faster-whisper"):
        reasons.append("NVIDIA CUDA GPU detected")
        reasons.append("faster-whisper (CTranslate2) is efficient on CUDA")
        return "faster-whisper", reasons, warnings

    if is_avail("whisper.cpp"):
        reasons.append("no MLX/CUDA path available; whisper.cpp is quantization-friendly on CPU")
        return "whisper.cpp", reasons, warnings

    for backend in SUPPORTED_BACKENDS:
        if is_avail(backend):
            reasons.append(f"using first available backend: {backend}")
            return backend, reasons, warnings

    raise NoBackendAvailableError(SUPPORTED_BACKENDS)
