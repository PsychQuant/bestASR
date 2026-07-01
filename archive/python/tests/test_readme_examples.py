"""Task 6.8 — README and example scripts are present and non-trivial."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_readme_has_quick_start_and_positioning():
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert "Quick start" in readme
    # The moat: bestASR explains *why* a model was chosen.
    assert "explains" in readme.lower()
    assert "bestasr diagnose" in readme


def test_example_scripts_exist_and_reference_cli():
    examples = {
        "diagnose.sh": "bestasr diagnose",
        "recommend.sh": "bestasr recommend",
        "basic_transcribe.sh": "bestasr transcribe",
    }
    for name, needle in examples.items():
        script = ROOT / "examples" / name
        assert script.is_file(), f"missing example: {name}"
        assert needle in script.read_text(encoding="utf-8")
