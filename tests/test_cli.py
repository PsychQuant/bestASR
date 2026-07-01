"""CLI behavior tests (task 1.1 help surface + tasks 6.1-6.7)."""

import json

import pytest

from bestasr import cli
from bestasr.cli import main
from bestasr.engines.base import Transcript, TranscriptSegment

ALL_AVAILABLE = {"mlx-whisper": True, "faster-whisper": True, "whisper.cpp": True}


class _FakeEngine:
    """Stand-in engine so transcribe tests never invoke a real backend."""

    name = "fake"

    def transcribe(self, audio_path, options):
        return Transcript(
            text="hello world",
            language="en",
            duration=2.5,
            backend="fake",
            model=options.model,
            segments=[TranscriptSegment(id=1, start=0.0, end=2.5, text="hello world")],
        )


@pytest.fixture
def audio_file(tmp_path):
    path = tmp_path / "clip.wav"
    path.write_bytes(b"RIFF....WAVEfmt ")  # not real audio; probing degrades gracefully
    return str(path)


@pytest.fixture
def fake_backend(monkeypatch):
    monkeypatch.setattr(cli, "engine_availability", lambda: dict(ALL_AVAILABLE))
    monkeypatch.setattr(cli, "get_engine", lambda name: _FakeEngine())


# --- 1.1 / 6.1 help surface ---

def test_help_exits_zero_and_lists_subcommands(capsys):
    with pytest.raises(SystemExit) as exc:
        main(["--help"])
    assert exc.value.code == 0
    out = capsys.readouterr().out
    for sub in ("diagnose", "recommend", "transcribe", "list-backends", "list-models"):
        assert sub in out


# --- 6.2 diagnose ---

def test_diagnose_prints_environment_and_recommendation(capsys):
    rc = main(["diagnose"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "System:" in out
    assert "Recommendation:" in out


# --- 6.3 recommend emits JSON only ---

def test_recommend_outputs_single_json(monkeypatch, capsys, audio_file):
    monkeypatch.setattr(cli, "engine_availability", lambda: dict(ALL_AVAILABLE))
    rc = main(["recommend", audio_file])
    out = capsys.readouterr().out
    assert rc == 0
    data = json.loads(out)  # entire stdout is one JSON object
    for key in ("backend", "model", "compute_type", "reason"):
        assert key in data


# --- 6.4 transcribe with options + defaults ---

def test_transcribe_writes_requested_format(fake_backend, audio_file, tmp_path):
    rc = main(["transcribe", audio_file, "--format", "srt"])
    assert rc == 0
    assert (tmp_path / "clip.srt").exists()


def test_transcribe_defaults_to_txt(fake_backend, audio_file, tmp_path):
    rc = main(["transcribe", audio_file])
    assert rc == 0
    assert (tmp_path / "clip.txt").read_text(encoding="utf-8") == "hello world"


# --- 6.5 explain mode ---

def test_transcribe_explain_prints_reasons_without_polluting_output(
    fake_backend, audio_file, tmp_path, capsys
):
    rc = main(["transcribe", audio_file, "--explain"])
    captured = capsys.readouterr()
    assert rc == 0
    assert "because" in captured.err
    # The written transcript file contains only the transcript.
    assert (tmp_path / "clip.txt").read_text(encoding="utf-8") == "hello world"


# --- 6.6 list-backends / list-models ---

def test_list_backends_shows_availability(capsys):
    rc = main(["list-backends"])
    out = capsys.readouterr().out
    assert rc == 0
    for backend in ("mlx-whisper", "faster-whisper", "whisper.cpp"):
        assert backend in out


def test_list_models_lists_sizes(capsys):
    rc = main(["list-models"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "large-v3" in out
    assert "tiny" in out


# --- 6.7 non-zero exit on failure ---

def test_missing_audio_file_exits_nonzero(capsys):
    rc = main(["transcribe", "does-not-exist.mp3"])
    err = capsys.readouterr().err
    assert rc != 0
    assert "not found" in err
