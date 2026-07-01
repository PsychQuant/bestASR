"""mlx-whisper backend (Apple Silicon / Metal via MLX)."""

from __future__ import annotations

import platform

from bestasr.engines.base import BaseEngine, TranscribeOptions, module_available

# Maps bestASR model names to the MLX community HF repos used by mlx-whisper.
_MLX_REPOS = {
    "tiny": "mlx-community/whisper-tiny",
    "base": "mlx-community/whisper-base",
    "small": "mlx-community/whisper-small",
    "medium": "mlx-community/whisper-medium",
    "large-v3-turbo": "mlx-community/whisper-large-v3-turbo",
    "large-v3": "mlx-community/whisper-large-v3",
}


class MlxWhisperEngine(BaseEngine):
    name = "mlx-whisper"

    def is_available(self) -> bool:
        if platform.system() != "Darwin" or platform.machine() != "arm64":
            return False
        return module_available("mlx_whisper")

    def _transcribe_raw(
        self, audio_path: str, options: TranscribeOptions
    ) -> tuple[list[dict], str | None, float | None]:
        import mlx_whisper  # lazy import

        repo = _MLX_REPOS.get(options.model)
        result = mlx_whisper.transcribe(
            audio_path, path_or_hf_repo=repo, language=options.language
        )
        raw = [
            {"start": seg["start"], "end": seg["end"], "text": seg["text"]}
            for seg in result.get("segments", [])
        ]
        return raw, result.get("language", options.language), None
