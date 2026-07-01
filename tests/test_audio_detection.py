"""Audio probing and language resolution (tasks 2.5, 2.6, 2.7-audio)."""

from bestasr.detect import audio
from bestasr.detect.audio import AudioInfo, probe_audio
from bestasr.detect.language import resolve_language


# --- 2.5 Probe audio file properties (ffprobe present) ---

_FFPROBE_SAMPLE = {
    "format": {"format_name": "wav,pcm", "duration": "12.5"},
    "streams": [
        {"codec_type": "video"},
        {"codec_type": "audio", "sample_rate": "16000", "channels": 1},
    ],
}


def test_probe_uses_ffprobe_when_present(monkeypatch):
    monkeypatch.setattr(audio, "has_ffprobe", lambda: True)
    monkeypatch.setattr(audio, "ffprobe_audio", lambda path: _FFPROBE_SAMPLE)
    info = probe_audio("sample.wav")
    assert isinstance(info, AudioInfo)
    assert info.duration == 12.5
    assert info.format == "wav"
    assert info.sample_rate == 16000
    assert info.channels == 1


# --- 2.6 Determine transcription language ---

def test_resolve_language_explicit():
    assert resolve_language("zh") == "zh"


def test_resolve_language_auto_is_none():
    assert resolve_language("auto") is None
    assert resolve_language(None) is None
    assert resolve_language("") is None


def test_probe_records_explicit_language(monkeypatch):
    monkeypatch.setattr(audio, "has_ffprobe", lambda: True)
    monkeypatch.setattr(audio, "ffprobe_audio", lambda path: _FFPROBE_SAMPLE)
    info = probe_audio("sample.wav", requested_language="zh")
    assert info.language == "zh"


# --- 2.7 Graceful degradation when ffmpeg is unavailable ---

def test_missing_ffmpeg_degrades_to_extension(monkeypatch):
    monkeypatch.setattr(audio, "has_ffprobe", lambda: False)
    notes: list[str] = []
    info = probe_audio("clip.mp3", notes=notes)
    assert info.format == "mp3"
    assert info.duration is None
    assert any("ffmpeg" in n.lower() for n in notes)
