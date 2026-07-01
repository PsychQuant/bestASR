"""Hardware detection: CPU, RAM, GPU/VRAM, and CPU instruction sets.

Detection prefers the standard library and psutil, and degrades gracefully
when a probe is unavailable (design D7). Every function is written so its
underlying probe can be monkeypatched in tests.
"""

from __future__ import annotations

import os
import platform
import subprocess


def _note(notes: list[str] | None, message: str) -> None:
    if notes is not None:
        notes.append(message)


def detect_cpu() -> str:
    """Return a human-readable CPU description, never empty."""
    system = platform.system()
    if system == "Darwin":
        brand = _run(["sysctl", "-n", "machdep.cpu.brand_string"])
        if brand:
            return brand
    elif system == "Linux":
        model = _linux_cpu_model()
        if model:
            return model
    return platform.processor() or platform.machine() or "unknown"


def _linux_cpu_model() -> str | None:
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        return None
    return None


def _ram_via_psutil() -> float:
    import psutil  # optional dependency; ImportError handled by caller

    return psutil.virtual_memory().total / 1e9


def _ram_via_os() -> float | None:
    try:
        return (os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")) / 1e9
    except (ValueError, AttributeError, OSError):
        return None


def detect_ram_gb(notes: list[str] | None = None) -> float:
    """Return total RAM in GB, degrading to an OS probe when psutil is absent."""
    try:
        return round(_ram_via_psutil(), 1)
    except Exception:  # noqa: BLE001 - psutil missing or probe failed; degrade
        fallback = _ram_via_os()
        if fallback is not None:
            _note(notes, "psutil unavailable; RAM detected via OS probe (reduced precision)")
            return round(fallback, 1)
        _note(notes, "could not detect RAM; assuming 0 GB")
        return 0.0


def _gpu_via_nvidia_smi() -> tuple[str, float] | None:
    line = _run(
        [
            "nvidia-smi",
            "--query-gpu=name,memory.total",
            "--format=csv,noheader,nounits",
        ]
    )
    if not line:
        return None
    first = line.splitlines()[0]
    name, _, mem = first.partition(",")
    name = name.strip()
    try:
        vram_gb = round(float(mem.strip()) / 1024, 1)  # MiB -> GB
    except ValueError:
        return None
    if not name:
        return None
    return name, vram_gb


def detect_gpu() -> tuple[str | None, float | None]:
    """Return (gpu_name, vram_gb), or (None, None) when no discrete GPU is found."""
    try:
        result = _gpu_via_nvidia_smi()
    except Exception:  # noqa: BLE001 - no nvidia-smi / probe failed
        return None, None
    if result is None:
        return None, None
    return result


def detect_cpu_flags() -> tuple[bool, bool]:
    """Return (has_avx2, has_avx512). Apple Silicon has neither."""
    system = platform.system()
    if system == "Linux":
        flags = _linux_cpu_flags()
        return ("avx2" in flags, "avx512f" in flags)
    if system == "Darwin":
        if platform.machine() == "arm64":
            return False, False
        features = (
            _run(["sysctl", "-n", "machdep.cpu.leaf7_features"]) or ""
        ).lower()
        return ("avx2" in features, "avx512f" in features)
    return False, False


def _linux_cpu_flags() -> set[str]:
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("flags"):
                    return set(line.split(":", 1)[1].split())
    except OSError:
        return set()
    return set()


def _run(cmd: list[str]) -> str | None:
    """Run ``cmd`` and return stripped stdout, or None on any failure."""
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=10, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    out = result.stdout.strip()
    return out or None
