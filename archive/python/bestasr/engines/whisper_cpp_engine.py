"""whisper.cpp backend (via the pywhispercpp binding).

The binding reports segment timestamps in centiseconds; they are converted to
seconds before normalization.
"""

from __future__ import annotations

from bestasr.engines.base import BaseEngine, TranscribeOptions, module_available


class WhisperCppEngine(BaseEngine):
    name = "whisper.cpp"

    def is_available(self) -> bool:
        return module_available("pywhispercpp")

    def _transcribe_raw(
        self, audio_path: str, options: TranscribeOptions
    ) -> tuple[list[dict], str | None, float | None]:
        from pywhispercpp.model import Model  # lazy import

        model = Model(options.model)
        segments = model.transcribe(audio_path)
        raw = [
            {
                "start": seg.t0 / 100.0,  # centiseconds -> seconds
                "end": seg.t1 / 100.0,
                "text": seg.text,
            }
            for seg in segments
        ]
        return raw, options.language, None
