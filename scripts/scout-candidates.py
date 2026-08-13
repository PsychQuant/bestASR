#!/usr/bin/env python3
"""Emit docs/model-catalog-candidates.csv — models reachable in the ecosystems
bestASR already talks to, that its catalog does NOT currently carry.

Provenance: every repo id below was READ from a live listing during the #183
scout (2026-08-13), never recalled or guessed — the repo rule is "repo ids are
never guessed; a pinned revision proves the probe". Sources, in the order they
were fetched:

  1. https://huggingface.co/FluidInference/models          (page 1 of 2; 30 of 59 shown)
  2. https://huggingface.co/models?other=mlx&pipeline_tag=automatic-speech-recognition&sort=downloads
                                                            (page 1 of 16; 30 of 472 shown)
  3. https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/main   (complete)

WHAT IS AND IS NOT VERIFIED HERE
  - `repo_id`        : read from the listing. Trustworthy.
  - `downloads`      : read from the listing where shown. Blank where not shown.
  - `languages`      : **mostly unverified.** The HF listing pages do not expose
                       language tags. Anything not stated in the repo id itself
                       is marked `unverified` — do not treat it as fact. The one
                       exception is names that carry a language token (`-ja`,
                       `-zh-cn`, `.en`).
  - `revision`       : NOT fetched. Adding any of these to the grid requires a
                       pinned commit sha per the supply-chain rule; that probe
                       has not been done.
  - `est_memory_gb`  : NOT estimated. Would need the model card / file sizes.

So this file is a **shortlist to triage**, not a catalog delta. Nothing here is
ready to add without a per-row probe.
"""

import csv
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "model-catalog-candidates.csv")

# (repo_id, ecosystem, family, language_signal, lang_verified, downloads, note)
CANDIDATES = [
    # ---- FluidInference / CoreML — the ecosystem bestASR already links against.
    ("FluidInference/paraformer-large-zh-coreml", "fluidaudio", "paraformer", "zh", "from repo id", "",
     "ALREADY CATALOGUED as fluid-paraformer|paraformer|large-zh|default with NO hf_repo — this fills that gap"),
    ("FluidInference/parakeet-ctc-0.6b-zh-cn-coreml", "fluidaudio", "parakeet", "zh-CN", "from repo id", "",
     "dedicated Chinese parakeet; bestASR has no zh parakeet"),
    ("FluidInference/parakeet-0.6b-ja-coreml", "fluidaudio", "parakeet", "ja", "from repo id", "",
     "dedicated Japanese parakeet; bestASR has no ja parakeet"),
    ("FluidInference/parakeet-unified-en-0.6b-coreml", "fluidaudio", "parakeet", "en", "from repo id", "",
     "relates to parked issue #123 (idd/123-parakeet-unified)"),
    ("FluidInference/canary-1b-v2-coreml", "fluidaudio", "canary", "unknown", "unverified", "",
     "CoreML canary; bestASR carries the MLX build only"),
    ("FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML", "fluidaudio", "nemotron-asr",
     "multi", "from repo id", "", "CoreML nemotron; bestASR carries the MLX build only"),
    ("FluidInference/nemotron-speech-streaming-en-0.6b-coreml", "fluidaudio", "nemotron-speech", "en",
     "from repo id", "", "English streaming variant"),
    ("FluidInference/parakeet-ctc-110m-coreml", "fluidaudio", "parakeet", "unknown", "unverified", "",
     "small parakeet, CTC head"),
    ("FluidInference/cohere-transcribe-03-2026-coreml", "fluidaudio", "cohere-transcribe", "unknown",
     "unverified", "", "new family; MLX sibling also exists (see below)"),

    # ---- mlx-community and friends — read from the MLX ASR listing, by downloads.
    ("mlx-community/parakeet-tdt-0.6b-v2", "mlx-audio", "parakeet", "unknown", "unverified", "1.87M",
     "HIGHER downloads than the v3 bestASR carries; predecessor version"),
    ("mlx-community/parakeet-tdt_ctc-0.6b-ja", "mlx-audio", "parakeet", "ja", "from repo id", "4.04k",
     "Japanese parakeet in MLX"),
    ("mlx-community/parakeet-tdt_ctc-110m", "mlx-audio", "parakeet", "unknown", "unverified", "104k",
     "small parakeet"),
    ("mlx-community/parakeet-tdt-1.1b", "mlx-audio", "parakeet", "unknown", "unverified", "1.2k",
     "larger parakeet"),
    ("mlx-community/whisper-large-v3-turbo-4bit", "mlx-audio", "whisper", "multi", "unverified", "4.52k",
     "EXPLICIT quant variant of a model bestASR records as quantization=default"),
    ("mlx-community/whisper-large-v3-turbo-8bit", "mlx-audio", "whisper", "multi", "unverified", "1.06k",
     "EXPLICIT quant variant of a model bestASR records as quantization=default"),
    ("mlx-community/whisper-large-v3-turbo-fp16", "mlx-audio", "whisper", "multi", "unverified", "669",
     "EXPLICIT quant variant of a model bestASR records as quantization=default"),
    ("mlx-community/whisper-large-v3-mlx", "mlx-audio", "whisper", "multi", "unverified", "25.7k", ""),
    ("mlx-community/whisper-small-mlx", "mlx-audio", "whisper", "multi", "unverified", "28.3k", ""),
    ("mlx-community/whisper-medium-mlx", "mlx-audio", "whisper", "multi", "unverified", "4.45k", ""),
    ("mlx-community/whisper-base-mlx", "mlx-audio", "whisper", "multi", "unverified", "5.68k", ""),
    ("BRlin/Breeze-ASR-25-mlx-fp16", "mlx-audio", "breeze-asr", "zh-TW?", "unverified", "1.71k",
     "Breeze is a Traditional-Chinese model family; zh-TW claim NOT verified from the listing"),
    ("BRlin/Breeze-ASR-25-mlx-bf16", "mlx-audio", "breeze-asr", "zh-TW?", "unverified", "1.51k",
     "as above; bf16 sibling"),
    ("mlx-community/MiMo-V2.5-ASR-MLX-8bit", "mlx-audio", "mimo-asr", "unknown", "unverified", "558",
     "language coverage NOT verified"),
    ("aufklarer/Qwen3-ASR-1.7B-MLX-4bit", "mlx-audio", "qwen3-asr", "unknown", "unverified", "784",
     "larger than the qwen3-asr/small bestASR carries"),
    ("beshkenadze/cohere-transcribe-03-2026-mlx-8bit", "mlx-audio", "cohere-transcribe", "unknown",
     "unverified", "495", "MLX sibling of the FluidInference CoreML build"),
    ("aufklarer/MOSS-Transcribe-Diarize-0.9B-MLX-5bit", "mlx-audio", "moss-transcribe", "unknown",
     "unverified", "1.1k", "transcribe + diarize in one model"),
    ("majentik/MOSS-Transcribe-preview-2B-MLX-6bit", "mlx-audio", "moss-transcribe", "unknown",
     "unverified", "601", ""),
    ("ai-babai/gigaam-multilingual-mlx", "mlx-audio", "gigaam", "multi", "unverified", "451", ""),
    ("al-bo/gigaam-v3-rnnt-mlx", "mlx-audio", "gigaam", "unknown", "unverified", "320", ""),
    ("leope/ark-asr-0.6B-mlx", "mlx-audio", "ark-asr", "unknown", "unverified", "2.68k", ""),
    ("leope/ark-asr-3B-mlx", "mlx-audio", "ark-asr", "unknown", "unverified", "1.17k", ""),
    ("NielsPeter/parakeet-tdt-0.6b-v3-mlx-bf16", "mlx-audio", "parakeet", "unknown", "unverified", "2.31k",
     "bf16 build of the v3 bestASR already carries"),
]

# WhisperKit publishes named variants; bestASR records all six of its rows as
# quantization="default". These are the actual folder names in the repo tree —
# the full listing, fetched complete (not paginated).
WHISPERKIT_VARIANTS = [
    "distil-whisper_distil-large-v3", "distil-whisper_distil-large-v3_594MB",
    "distil-whisper_distil-large-v3_turbo", "distil-whisper_distil-large-v3_turbo_600MB",
    "openai_whisper-base", "openai_whisper-base.en",
    "openai_whisper-large-v2", "openai_whisper-large-v2_949MB",
    "openai_whisper-large-v2_turbo", "openai_whisper-large-v2_turbo_955MB",
    "openai_whisper-large-v3", "openai_whisper-large-v3-v20240930",
    "openai_whisper-large-v3-v20240930_547MB", "openai_whisper-large-v3-v20240930_626MB",
    "openai_whisper-large-v3-v20240930_turbo", "openai_whisper-large-v3-v20240930_turbo_632MB",
    "openai_whisper-large-v3_947MB", "openai_whisper-large-v3_turbo",
    "openai_whisper-large-v3_turbo_954MB",
    "openai_whisper-medium", "openai_whisper-medium.en",
    "openai_whisper-small", "openai_whisper-small.en",
    "openai_whisper-small.en_217MB", "openai_whisper-small_216MB",
    "openai_whisper-tiny", "openai_whisper-tiny.en",
]


def main():
    fields = ["repo_id", "ecosystem", "family", "language_signal", "language_evidence",
              "downloads", "in_catalog", "note"]
    rows = [dict(zip(fields[:6], c[:6]), in_catalog="no", note=c[6]) for c in CANDIDATES]

    # WhisperKit variants are a different shape: they are not "new models" but the
    # named alternatives that `quantization=default` currently hides.
    for v in WHISPERKIT_VARIANTS:
        lang = "en-only" if ".en" in v else "multi"
        rows.append({
            "repo_id": f"argmaxinc/whisperkit-coreml :: {v}",
            "ecosystem": "whisperkit", "family": "whisper",
            "language_signal": lang, "language_evidence": "from variant name",
            "downloads": "", "in_catalog": "variant-of-existing-row",
            "note": "published variant that bestASR's quantization=default does not distinguish",
        })

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    new = sum(1 for r in rows if r["in_catalog"] == "no")
    var = sum(1 for r in rows if r["in_catalog"] == "variant-of-existing-row")
    zh_ja = sum(1 for r in rows if r["in_catalog"] == "no"
                and any(t in r["language_signal"] for t in ("zh", "ja")))
    print(f"wrote {os.path.normpath(OUT)}")
    print(f"  {new} candidate models not in the catalog")
    print(f"  {var} WhisperKit variants hidden behind quantization=default")
    print(f"  {zh_ja} of the candidates signal zh or ja in their repo id")


if __name__ == "__main__":
    main()
