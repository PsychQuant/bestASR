"""faster-whisper (CTranslate2) backend."""

from __future__ import annotations

from bestasr.engines.base import BaseEngine, TranscribeOptions, module_available


class FasterWhisperEngine(BaseEngine):
    name = "faster-whisper"

    def is_available(self) -> bool:
        return module_available("faster_whisper")

    def _transcribe_raw(
        self, audio_path: str, options: TranscribeOptions
    ) -> tuple[list[dict], str | None, float | None]:
        from faster_whisper import WhisperModel  # lazy import

        model = WhisperModel(options.model, compute_type=options.compute_type)
        segments, info = model.transcribe(audio_path, language=options.language)
        raw = [
            {
                "start": seg.start,
                "end": seg.end,
                "text": seg.text,
                "confidence": getattr(seg, "avg_logprob", None),
            }
            for seg in segments
        ]
        return raw, getattr(info, "language", None), getattr(info, "duration", None)
