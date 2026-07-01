"""Detection-layer tests (tasks 2.1-2.4, plus RAM/GPU degradation for 2.2/2.7)."""

from bestasr.detect import acceleration, hardware
from bestasr.detect.system import SystemInfo, detect_system
from bestasr.utils import ffmpeg


# --- 2.1 Detect operating system and CPU ---

def test_detect_cpu_non_empty():
    cpu = hardware.detect_cpu()
    assert cpu
    assert isinstance(cpu, str)


def test_detect_system_reports_os_and_cpu():
    info = detect_system()
    assert isinstance(info, SystemInfo)
    assert info.os
    assert info.cpu


# --- 2.2 Detect memory and GPU ---

def test_detect_ram_positive_on_host():
    assert hardware.detect_ram_gb() > 0


def test_detect_ram_degrades_when_psutil_missing(monkeypatch):
    def _boom():
        raise ImportError("no psutil")

    monkeypatch.setattr(hardware, "_ram_via_psutil", _boom)
    monkeypatch.setattr(hardware, "_ram_via_os", lambda: 8.0)
    notes: list[str] = []
    assert hardware.detect_ram_gb(notes=notes) == 8.0
    assert any("psutil" in n.lower() for n in notes)


def test_detect_gpu_none_when_no_nvidia(monkeypatch):
    monkeypatch.setattr(hardware, "_gpu_via_nvidia_smi", lambda: None)
    assert hardware.detect_gpu() == (None, None)


def test_detect_gpu_reports_nvidia(monkeypatch):
    monkeypatch.setattr(
        hardware, "_gpu_via_nvidia_smi", lambda: ("NVIDIA GeForce RTX 3060", 6.0)
    )
    gpu, vram = hardware.detect_gpu()
    assert gpu == "NVIDIA GeForce RTX 3060"
    assert vram == 6.0


# --- 2.3 Detect acceleration backends (graceful) ---

def test_has_mlx_false_off_apple_silicon(monkeypatch):
    monkeypatch.setattr(acceleration.platform, "system", lambda: "Linux")
    assert acceleration.has_mlx() is False


def test_absent_acceleration_reported_as_false_not_error(monkeypatch):
    monkeypatch.setattr(acceleration.platform, "system", lambda: "Darwin")
    monkeypatch.setattr(acceleration.platform, "machine", lambda: "arm64")

    def _boom(_name):
        raise ImportError("probe failed")

    monkeypatch.setattr(acceleration, "_can_import", _boom)
    # Must not raise; must report unavailable.
    assert acceleration.has_mlx() is False


def test_detect_mlx_on_apple_silicon(monkeypatch):
    monkeypatch.setattr(acceleration.platform, "system", lambda: "Darwin")
    monkeypatch.setattr(acceleration.platform, "machine", lambda: "arm64")
    monkeypatch.setattr(acceleration, "_can_import", lambda name: name == "mlx_whisper")
    assert acceleration.has_metal() is True
    assert acceleration.has_mlx() is True


# --- 2.4 Detect CPU instruction sets and ffmpeg presence ---

def test_has_ffmpeg_reflects_path(monkeypatch):
    monkeypatch.setattr(ffmpeg.shutil, "which", lambda name: "/usr/bin/ffmpeg")
    assert ffmpeg.has_ffmpeg() is True
    monkeypatch.setattr(ffmpeg.shutil, "which", lambda name: None)
    assert ffmpeg.has_ffmpeg() is False


def test_cpu_flags_return_booleans():
    avx2, avx512 = hardware.detect_cpu_flags()
    assert isinstance(avx2, bool)
    assert isinstance(avx512, bool)
