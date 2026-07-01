"""Task 1.2 — core dataclasses exist with the fields named in the design contract."""

import dataclasses

from bestasr.detect.system import SystemInfo
from bestasr.detect.audio import AudioInfo
from bestasr.router.recommendation import ASRRecommendation
from bestasr.engines.base import Transcript, TranscriptSegment, TranscribeOptions
from bestasr.models.requirements import ModelRequirements


def _field_names(cls) -> set[str]:
    return {f.name for f in dataclasses.fields(cls)}


def test_system_info_fields():
    assert _field_names(SystemInfo) == {
        "os", "cpu", "ram_gb", "gpu", "vram_gb",
        "has_cuda", "has_metal", "has_mlx",
        "has_avx2", "has_avx512", "has_ffmpeg",
    }


def test_audio_info_fields():
    assert _field_names(AudioInfo) == {
        "path", "duration", "format", "sample_rate", "channels", "language",
    }


def test_recommendation_fields():
    assert _field_names(ASRRecommendation) == {
        "backend", "model", "compute_type", "profile", "language",
        "estimated_speed", "estimated_accuracy", "reason", "warnings",
    }


def test_transcript_segment_fields():
    assert _field_names(TranscriptSegment) == {
        "id", "start", "end", "text", "confidence",
    }


def test_transcript_fields():
    assert _field_names(Transcript) == {
        "text", "language", "duration", "segments", "backend", "model",
    }


def test_transcribe_options_fields():
    assert _field_names(TranscribeOptions) == {
        "model", "compute_type", "language",
    }


def test_model_requirements_fields():
    assert _field_names(ModelRequirements) == {"model", "ram_gb", "vram_gb"}


def test_recommendation_reason_and_warnings_default_empty():
    rec = ASRRecommendation(
        backend="whisper.cpp",
        model="small",
        compute_type="int8",
        profile="balanced",
        language=None,
        estimated_speed="medium",
        estimated_accuracy="medium",
    )
    assert rec.reason == []
    assert rec.warnings == []


def test_transcript_segment_confidence_optional():
    seg = TranscriptSegment(id=1, start=0.0, end=1.0, text="hi")
    assert seg.confidence is None
