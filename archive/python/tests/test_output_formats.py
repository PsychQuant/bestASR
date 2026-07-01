"""Output-writer tests (tasks 4.1-4.5), anchored on the spec SBE examples."""

import json

import pytest

from bestasr import output


# --- 4.1 Write plain text output ---

def test_txt_render_contains_text(sample_transcript):
    assert output.render(sample_transcript, "txt") == "hello world"


def test_txt_write_to_file(sample_transcript, tmp_path):
    path = tmp_path / "out.txt"
    output.write_transcript(sample_transcript, str(path), "txt")
    assert path.read_text(encoding="utf-8") == "hello world"


# --- 4.2 Write JSON output ---

def test_json_parseable_and_complete(sample_transcript):
    data = json.loads(output.render(sample_transcript, "json"))
    for key in ("text", "language", "duration", "backend", "model", "segments"):
        assert key in data
    seg = data["segments"][0]
    assert seg == {"id": 1, "start": 0.0, "end": 2.5, "text": "hello world", "confidence": None}


# --- 4.3 Write SRT subtitles (SBE example) ---

def test_srt_single_segment_matches_example(sample_transcript):
    rendered = output.render(sample_transcript, "srt")
    assert "1\n00:00:00,000 --> 00:00:02,500\nhello world" in rendered


# --- 4.4 Write WebVTT subtitles (SBE example) ---

def test_vtt_header_and_cue(sample_transcript):
    rendered = output.render(sample_transcript, "vtt")
    assert rendered.splitlines()[0] == "WEBVTT"
    assert "00:00:00.000 --> 00:00:02.500\nhello world" in rendered


# --- 4.5 Select writer by format with a default ---

def test_default_format_is_txt(sample_transcript):
    assert output.render(sample_transcript) == output.render(sample_transcript, "txt")


def test_unsupported_format_raises(sample_transcript):
    with pytest.raises(output.UnsupportedFormatError) as exc:
        output.render(sample_transcript, "docx")
    for fmt in ("txt", "json", "srt", "vtt"):
        assert fmt in str(exc.value)
