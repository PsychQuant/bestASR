"""Engine-layer tests (tasks 5.1-5.6)."""

import pytest

from bestasr.engines import get_engines
from bestasr.engines.base import BaseEngine, TranscribeOptions, TranscriptionError
from bestasr.engines import faster_whisper_engine, mlx_whisper_engine, whisper_cpp_engine
from bestasr.engines.faster_whisper_engine import FasterWhisperEngine
from bestasr.engines.mlx_whisper_engine import MlxWhisperEngine
from bestasr.engines.whisper_cpp_engine import WhisperCppEngine
from bestasr.models.requirements import ModelRequirements

OPTS = TranscribeOptions(model="small", compute_type="int8", language="en")


# --- 5.1 Common engine interface ---

@pytest.mark.parametrize("engine", get_engines(), ids=lambda e: e.name)
def test_engine_implements_interface(engine):
    assert isinstance(engine, BaseEngine)
    assert callable(engine.is_available)
    assert callable(engine.transcribe)
    assert callable(engine.estimate_requirements)


def test_estimate_requirements_returns_positive():
    req = FasterWhisperEngine().estimate_requirements("medium")
    assert isinstance(req, ModelRequirements)
    assert req.ram_gb > 0


# --- 5.2 Availability detection is graceful ---

def test_faster_whisper_available_reflects_module(monkeypatch):
    monkeypatch.setattr(faster_whisper_engine, "module_available", lambda name: False)
    assert FasterWhisperEngine().is_available() is False
    monkeypatch.setattr(faster_whisper_engine, "module_available", lambda name: True)
    assert FasterWhisperEngine().is_available() is True


def test_availability_never_raises_when_module_missing():
    # pywhispercpp is not installed in this environment; must report False, not raise.
    assert WhisperCppEngine().is_available() in (True, False)


# --- 5.3 Transcription returns a normalized Transcript ---

def test_transcribe_normalizes_segments(monkeypatch):
    engine = FasterWhisperEngine()
    unsorted_raw = [
        {"start": 1.0, "end": 2.5, "text": " world"},
        {"start": 0.0, "end": 1.0, "text": "hello"},
    ]
    monkeypatch.setattr(
        engine, "_transcribe_raw", lambda audio_path, options: (unsorted_raw, "en", 2.5)
    )
    transcript = engine.transcribe("clip.wav", OPTS)
    assert [s.id for s in transcript.segments] == [1, 2]
    assert [s.start for s in transcript.segments] == [0.0, 1.0]  # ordered
    assert transcript.text == "hello world"
    assert transcript.backend == "faster-whisper"
    assert transcript.model == "small"
    assert transcript.duration == 2.5


# --- 5.4 / 5.5 whisper.cpp and mlx via mocked raw transcription ---

def test_whisper_cpp_transcribe_mocked(monkeypatch):
    engine = WhisperCppEngine()
    monkeypatch.setattr(
        engine,
        "_transcribe_raw",
        lambda audio_path, options: ([{"start": 0.0, "end": 1.0, "text": "hi"}], "en", None),
    )
    transcript = engine.transcribe("clip.wav", OPTS)
    assert transcript.backend == "whisper.cpp"
    assert transcript.text == "hi"


def test_mlx_transcribe_mocked(monkeypatch):
    engine = MlxWhisperEngine()
    monkeypatch.setattr(
        engine,
        "_transcribe_raw",
        lambda audio_path, options: ([{"start": 0.0, "end": 2.0, "text": "hola"}], "es", 2.0),
    )
    transcript = engine.transcribe("clip.wav", OPTS)
    assert transcript.backend == "mlx-whisper"
    assert transcript.language == "es"


def test_mlx_is_available_false_off_apple_silicon(monkeypatch):
    monkeypatch.setattr(mlx_whisper_engine.platform, "system", lambda: "Linux")
    assert MlxWhisperEngine().is_available() is False


# --- 5.6 Transcription failure is surfaced ---

def test_backend_failure_wrapped_in_transcription_error(monkeypatch):
    engine = FasterWhisperEngine()

    def _boom(audio_path, options):
        raise ValueError("decode error")

    monkeypatch.setattr(engine, "_transcribe_raw", _boom)
    with pytest.raises(TranscriptionError) as exc:
        engine.transcribe("broken.wav", OPTS)
    assert "faster-whisper" in str(exc.value)
