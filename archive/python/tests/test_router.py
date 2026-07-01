"""Routing-layer tests (tasks 3.1-3.8)."""

import pytest

from bestasr.models.registry import SUPPORTED_MODELS
from bestasr.models.requirements import ModelRequirements, requirements_for
from bestasr.router.profiles import (
    DEFAULT_PROFILE,
    PROFILES,
    profile_models,
    profile_weights,
)
from bestasr.router.recommendation import recommend
from bestasr.router.rules import NoBackendAvailableError, select_backend
from bestasr.router.scorer import ensure_fits, select_compute_type, select_model

ALL_AVAILABLE = {"mlx-whisper": True, "faster-whisper": True, "whisper.cpp": True}


# --- 3.1 Profile weight table (design D9) ---

def test_profiles_present_and_default():
    assert set(PROFILES) == {"fast", "balanced", "accurate"}
    assert DEFAULT_PROFILE == "balanced"


@pytest.mark.parametrize("name", ["fast", "balanced", "accurate"])
def test_profile_weights_sum_to_one(name):
    assert round(sum(profile_weights(name).values()), 6) == 1.0


def test_profile_models_lists():
    assert profile_models("fast") == ["tiny", "base", "small"]
    assert profile_models("balanced") == ["small", "medium"]


def test_unknown_profile_raises():
    with pytest.raises(ValueError):
        profile_weights("turbo-mode")


# --- 3.2 Estimate model requirements ---

@pytest.mark.parametrize("model", SUPPORTED_MODELS)
def test_requirements_positive_for_each_model(model):
    req = requirements_for(model)
    assert isinstance(req, ModelRequirements)
    assert req.ram_gb > 0
    assert req.vram_gb > 0


# --- 3.3 Backend decision table ---

def test_apple_silicon_selects_mlx(apple_silicon_system):
    backend, reasons, _ = select_backend(apple_silicon_system, ALL_AVAILABLE)
    assert backend == "mlx-whisper"
    assert any("Apple Silicon" in r for r in reasons)


def test_cuda_selects_faster_whisper(cuda_system):
    backend, reasons, _ = select_backend(cuda_system, ALL_AVAILABLE)
    assert backend == "faster-whisper"
    assert any("CUDA" in r for r in reasons)


def test_cpu_only_selects_whisper_cpp(cpu_only_system):
    backend, _, _ = select_backend(cpu_only_system, ALL_AVAILABLE)
    assert backend == "whisper.cpp"


# --- 3.4 Select model and compute type by profile scoring ---

@pytest.mark.parametrize(
    "profile,expected",
    [("fast", "small"), ("balanced", "medium"), ("accurate", "large-v3")],
)
def test_profile_selects_model_when_all_fit(profile, expected):
    # avail_mem = 16 GB fits every model up to large-v3 (SBE example).
    model, _, warnings = select_model(profile, 16.0, "whisper.cpp")
    assert model == expected
    assert warnings == []


def test_compute_type_by_backend(apple_silicon_system, cuda_system):
    assert select_compute_type("mlx-whisper", apple_silicon_system) == "fp16"
    assert select_compute_type("faster-whisper", cuda_system) == "int8_float16"  # 6 GB < 8
    assert select_compute_type("whisper.cpp", cpu_only := apple_silicon_system) == "int8"


def test_compute_type_fp16_when_vram_ample(cuda_system):
    from dataclasses import replace

    big = replace(cuda_system, vram_gb=12.0)
    assert select_compute_type("faster-whisper", big) == "fp16"


def test_compute_type_int8_when_vram_very_low(cuda_system):
    from dataclasses import replace

    tiny_gpu = replace(cuda_system, vram_gb=3.0)  # < 4 GB -> most aggressive
    assert select_compute_type("faster-whisper", tiny_gpu) == "int8"


# --- 3.5 Downgrade model when memory is insufficient (SBE example) ---

@pytest.mark.parametrize(
    "avail,expected,n_warnings",
    [(16.0, "large-v3", 0), (6.0, "medium", 1), (3.0, "small", 2)],
)
def test_downgrade_steps(avail, expected, n_warnings):
    model, warnings, _ = ensure_fits("large-v3", avail, "whisper.cpp")
    assert model == expected
    assert len(warnings) == n_warnings


# --- 3.4 integration + 3.7 explainable ---

@pytest.mark.parametrize(
    "profile,expected_model",
    [("fast", "small"), ("balanced", "medium"), ("accurate", "large-v3")],
)
def test_recommend_on_apple_silicon(apple_silicon_system, profile, expected_model):
    rec = recommend(apple_silicon_system, profile=profile, available=ALL_AVAILABLE)
    assert rec.backend == "mlx-whisper"
    assert rec.model == expected_model
    assert rec.compute_type == "fp16"
    assert rec.reason  # 3.7 — non-empty reasoning


# --- 3.6 Honor explicit backend override with fallback ---

def test_requested_backend_unavailable_falls_back(cpu_only_system):
    available = {"mlx-whisper": False, "faster-whisper": False, "whisper.cpp": True}
    rec = recommend(
        cpu_only_system, backend_override="faster-whisper", available=available
    )
    assert rec.backend == "whisper.cpp"
    assert any("faster-whisper" in w for w in rec.warnings)


# --- 3.8 Handle absence of any available backend ---

def test_no_backend_available_raises(cpu_only_system):
    none_available = {"mlx-whisper": False, "faster-whisper": False, "whisper.cpp": False}
    with pytest.raises(NoBackendAvailableError) as exc:
        recommend(cpu_only_system, available=none_available)
    for backend in ("mlx-whisper", "faster-whisper", "whisper.cpp"):
        assert backend in str(exc.value)
