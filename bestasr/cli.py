"""bestASR command-line entry point (design D1/D10).

Wires the five-layer pipeline (detect -> route -> engine -> output) behind an
argparse command surface using only the standard library. Command handlers
raise typed errors; ``main`` maps them to clear messages and exit codes.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from bestasr import __version__, output
from bestasr.detect.audio import probe_audio
from bestasr.detect.system import SystemInfo, detect_system
from bestasr.engines import availability as engine_availability
from bestasr.engines import get_engine
from bestasr.engines.base import TranscribeOptions, TranscriptionError
from bestasr.models.registry import SUPPORTED_MODELS
from bestasr.output import SUPPORTED_FORMATS, UnsupportedFormatError
from bestasr.router.profiles import DEFAULT_PROFILE, PROFILE_NAMES
from bestasr.router.recommendation import recommend, to_dict
from bestasr.router.rules import NoBackendAvailableError, SUPPORTED_BACKENDS

# Exit codes: 0 ok, 1 runtime failure, 2 usage/input error.
EXIT_OK = 0
EXIT_RUNTIME = 1
EXIT_USAGE = 2


class UsageError(Exception):
    """A user input problem that maps to a non-zero exit (missing file, etc.)."""


# --------------------------------------------------------------------------- #
# Parser
# --------------------------------------------------------------------------- #

def _add_selection_flags(parser: argparse.ArgumentParser, *, with_output: bool) -> None:
    parser.add_argument(
        "--profile", choices=PROFILE_NAMES, default=DEFAULT_PROFILE,
        help="Optimization profile (default: %(default)s)",
    )
    parser.add_argument(
        "--backend", choices=["auto", *SUPPORTED_BACKENDS], default="auto",
        help="Force a backend (default: auto)",
    )
    parser.add_argument(
        "--model", choices=["auto", *SUPPORTED_MODELS], default="auto",
        help="Force a model size (default: auto)",
    )
    parser.add_argument(
        "--language", default="auto",
        help="Audio language code, or 'auto' (default: auto)",
    )
    if with_output:
        parser.add_argument(
            "--format", choices=SUPPORTED_FORMATS, default=output.DEFAULT_FORMAT,
            help="Output format (default: %(default)s)",
        )
        parser.add_argument("--output", help="Output file path (default: derived from input)")
        parser.add_argument(
            "--explain", action="store_true",
            help="Print why this backend/model was chosen",
        )


def build_parser() -> argparse.ArgumentParser:
    """Build the ``bestasr`` argument parser with all subcommands registered."""
    parser = argparse.ArgumentParser(
        prog="bestasr",
        description="Automatically choose the best local ASR model and backend for your machine.",
    )
    parser.add_argument("--version", action="version", version=f"bestasr {__version__}")
    sub = parser.add_subparsers(dest="command", metavar="<command>")

    sub.add_parser("diagnose", help="Detect this machine and print a recommendation")

    p_recommend = sub.add_parser(
        "recommend", help="Print a JSON recommendation for an audio file (no transcription)"
    )
    p_recommend.add_argument("audio", help="Path to the input audio file")
    _add_selection_flags(p_recommend, with_output=False)

    p_transcribe = sub.add_parser("transcribe", help="Transcribe an audio file")
    p_transcribe.add_argument("audio", help="Path to the input audio file")
    _add_selection_flags(p_transcribe, with_output=True)

    sub.add_parser("list-backends", help="List supported backends and their availability")
    sub.add_parser("list-models", help="List supported model sizes")

    return parser


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def _overrides(args: argparse.Namespace) -> tuple[str | None, str | None]:
    backend = None if args.backend == "auto" else args.backend
    model = None if args.model == "auto" else args.model
    return backend, model


def _require_file(path: str) -> None:
    if not os.path.isfile(path):
        raise UsageError(f"audio file not found: {path}")


def _print_reasons(rec, stream) -> None:
    for reason in rec.reason:
        print(f"  - {reason}", file=stream)
    for warning in rec.warnings:
        print(f"  ! {warning}", file=stream)


# --------------------------------------------------------------------------- #
# Command handlers
# --------------------------------------------------------------------------- #

def _cmd_diagnose(args: argparse.Namespace) -> int:
    notes: list[str] = []
    system = detect_system(notes=notes)
    _print_system(system)

    print("\nRecommendation:")
    try:
        rec = recommend(system, available=engine_availability())
    except NoBackendAvailableError as exc:
        print(f"  {exc}")
        _print_notes(notes)
        return EXIT_OK

    print(f"  Backend: {rec.backend}")
    print(f"  Model:   {rec.model}")
    print(f"  Compute: {rec.compute_type}")
    print(f"  Profile: {rec.profile}")
    print("Reason:")
    _print_reasons(rec, sys.stdout)
    _print_notes(notes)
    return EXIT_OK


def _cmd_recommend(args: argparse.Namespace) -> int:
    _require_file(args.audio)
    system = detect_system()
    audio = probe_audio(args.audio, requested_language=args.language)
    backend_override, model_override = _overrides(args)
    rec = recommend(
        system, audio, profile=args.profile,
        backend_override=backend_override, model_override=model_override,
        available=engine_availability(),
    )
    print(json.dumps(to_dict(rec), ensure_ascii=False, indent=2))
    return EXIT_OK


def _cmd_transcribe(args: argparse.Namespace) -> int:
    _require_file(args.audio)
    notes: list[str] = []
    system = detect_system(notes=notes)
    audio = probe_audio(args.audio, requested_language=args.language, notes=notes)
    backend_override, model_override = _overrides(args)
    rec = recommend(
        system, audio, profile=args.profile,
        backend_override=backend_override, model_override=model_override,
        available=engine_availability(),
    )

    engine = get_engine(rec.backend)
    options = TranscribeOptions(
        model=rec.model, compute_type=rec.compute_type,
        language=audio.language if audio.language is not None else rec.language,
    )
    transcript = engine.transcribe(audio.path, options)

    out_path = args.output or _derive_output_path(args.audio, args.format)
    output.write_transcript(transcript, out_path, args.format)
    print(f"Wrote {args.format} transcript to {out_path}")

    if args.explain:
        print(
            f"Selected {rec.backend} {rec.model} ({rec.compute_type}) because:",
            file=sys.stderr,
        )
        _print_reasons(rec, sys.stderr)
        for note in notes:
            print(f"  ! {note}", file=sys.stderr)
    return EXIT_OK


def _cmd_list_backends(args: argparse.Namespace) -> int:
    for name, available in engine_availability().items():
        status = "available" if available else "not installed"
        print(f"{name:16} {status}")
    return EXIT_OK


def _cmd_list_models(args: argparse.Namespace) -> int:
    for model in SUPPORTED_MODELS:
        print(model)
    return EXIT_OK


COMMANDS = {
    "diagnose": _cmd_diagnose,
    "recommend": _cmd_recommend,
    "transcribe": _cmd_transcribe,
    "list-backends": _cmd_list_backends,
    "list-models": _cmd_list_models,
}


# --------------------------------------------------------------------------- #
# Output helpers
# --------------------------------------------------------------------------- #

def _print_system(system: SystemInfo) -> None:
    accel = [
        name for name, on in (
            ("CUDA", system.has_cuda), ("Metal", system.has_metal), ("MLX", system.has_mlx)
        ) if on
    ]
    print("System:")
    print(f"  OS:  {system.os}")
    print(f"  CPU: {system.cpu}")
    print(f"  RAM: {system.ram_gb:g} GB")
    if system.gpu:
        print(f"  GPU: {system.gpu} ({system.vram_gb:g} GB VRAM)")
    print(f"  Acceleration: {', '.join(accel) if accel else 'none'}")
    print(f"  ffmpeg: {'yes' if system.has_ffmpeg else 'no'}")


def _print_notes(notes: list[str]) -> None:
    if notes:
        print("Notes:")
        for note in notes:
            print(f"  ! {note}")


def _derive_output_path(audio_path: str, fmt: str) -> str:
    base, _ = os.path.splitext(audio_path)
    return f"{base}.{fmt}"


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

def main(argv: list[str] | None = None) -> int:
    """Parse ``argv``, dispatch, and map known errors to exit codes."""
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.command:
        parser.print_help()
        return EXIT_OK

    try:
        return COMMANDS[args.command](args)
    except UsageError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_USAGE
    except (NoBackendAvailableError, TranscriptionError, UnsupportedFormatError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_RUNTIME


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
