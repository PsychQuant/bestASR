"""Shared pytest fixtures (task 1.3).

These let router and output tests run against fabricated inputs without any real
hardware probing or transcription.
"""

from __future__ import annotations

import pytest

from bestasr.detect.system import SystemInfo
from bestasr.detect.audio import AudioInfo
from bestasr.engines.base import Transcript, TranscriptSegment


@pytest.fixture
def apple_silicon_system() -> SystemInfo:
    return SystemInfo(
        os="macOS",
        cpu="Apple M3 Pro",
        ram_gb=36.0,
        gpu=None,
        vram_gb=None,
        has_cuda=False,
        has_metal=True,
        has_mlx=True,
        has_avx2=False,
        has_avx512=False,
        has_ffmpeg=True,
    )


@pytest.fixture
def cuda_system() -> SystemInfo:
    return SystemInfo(
        os="Linux",
        cpu="Intel Xeon",
        ram_gb=32.0,
        gpu="NVIDIA GeForce RTX 3060",
        vram_gb=6.0,
        has_cuda=True,
        has_metal=False,
        has_mlx=False,
        has_avx2=True,
        has_avx512=False,
        has_ffmpeg=True,
    )


@pytest.fixture
def cpu_only_system() -> SystemInfo:
    return SystemInfo(
        os="Linux",
        cpu="AMD Ryzen 5",
        ram_gb=8.0,
        gpu=None,
        vram_gb=None,
        has_cuda=False,
        has_metal=False,
        has_mlx=False,
        has_avx2=True,
        has_avx512=False,
        has_ffmpeg=True,
    )


@pytest.fixture
def sample_audio() -> AudioInfo:
    return AudioInfo(
        path="sample.wav",
        duration=12.5,
        format="wav",
        sample_rate=16000,
        channels=1,
        language=None,
    )


@pytest.fixture
def sample_transcript() -> Transcript:
    return Transcript(
        text="hello world",
        language="en",
        duration=2.5,
        backend="faster-whisper",
        model="small",
        segments=[
            TranscriptSegment(id=1, start=0.0, end=2.5, text="hello world"),
        ],
    )
