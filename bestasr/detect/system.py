"""``SystemInfo`` and the top-level system detection aggregator (design D7)."""

from __future__ import annotations

import platform
from dataclasses import dataclass

from bestasr.detect import acceleration, hardware
from bestasr.utils.ffmpeg import has_ffmpeg


@dataclass(frozen=True)
class SystemInfo:
    """Facts about the host machine relevant to ASR backend selection."""

    os: str
    cpu: str
    ram_gb: float
    gpu: str | None
    vram_gb: float | None
    has_cuda: bool
    has_metal: bool
    has_mlx: bool
    has_avx2: bool
    has_avx512: bool
    has_ffmpeg: bool


def detect_system(notes: list[str] | None = None) -> SystemInfo:
    """Detect the host environment, degrading gracefully on missing probes."""
    gpu, vram_gb = hardware.detect_gpu()
    has_avx2, has_avx512 = hardware.detect_cpu_flags()
    return SystemInfo(
        os=_os_name(),
        cpu=hardware.detect_cpu(),
        ram_gb=hardware.detect_ram_gb(notes=notes),
        gpu=gpu,
        vram_gb=vram_gb,
        has_cuda=acceleration.has_cuda(),
        has_metal=acceleration.has_metal(),
        has_mlx=acceleration.has_mlx(),
        has_avx2=has_avx2,
        has_avx512=has_avx512,
        has_ffmpeg=has_ffmpeg(),
    )


def _os_name() -> str:
    system = platform.system()
    return {"Darwin": "macOS", "Windows": "Windows", "Linux": "Linux"}.get(
        system, system or "unknown"
    )
