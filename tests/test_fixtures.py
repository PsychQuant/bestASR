"""Task 1.3 — confirm the pytest framework and shared fixtures work."""

from bestasr.detect.system import SystemInfo
from bestasr.detect.audio import AudioInfo
from bestasr.engines.base import Transcript


def test_system_fixtures_are_valid(apple_silicon_system, cuda_system, cpu_only_system):
    for info in (apple_silicon_system, cuda_system, cpu_only_system):
        assert isinstance(info, SystemInfo)
        assert info.ram_gb > 0
    assert apple_silicon_system.has_mlx is True
    assert cuda_system.has_cuda is True
    assert cpu_only_system.has_cuda is False


def test_audio_fixture_is_valid(sample_audio):
    assert isinstance(sample_audio, AudioInfo)
    assert sample_audio.sample_rate == 16000


def test_transcript_fixture_is_valid(sample_transcript):
    assert isinstance(sample_transcript, Transcript)
    assert sample_transcript.segments[0].text == "hello world"
