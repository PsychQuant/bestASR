# ASR Evaluation Landscape — references for bestASR benchmark expansion

> Source: `/deep-research` survey (2026-07-09), 104 agents, adversarial-verified
> (each claim ≥2/3 refute-vote survival). Every claim below carries its primary
> sources. This is a durable literature base for choosing benchmark corpora and
> eval methodology; it is **not** itself the corpus (see `## Actionable shortlist`).

## TL;DR for bestASR

- **English**: **LibriSpeech** is the single strongest immediate corpus —
  CC BY 4.0, **account-free**, small dev/test splits (~5h / ~346 MB each),
  plain-text ground truth. Fills bestASR's thin English corpus (#34 left en at 2/3).
- **Mandarin (Simplified)**: **AISHELL-1** is the clean equivalent (Apache 2.0,
  account-free, OpenSLR /33) — but it is **Simplified** Mandarin, not the
  Traditional Chinese (zh-TW) bestASR targets, and ships as one ~15 GB tarball.
- **Traditional Chinese (zh-TW) + Japanese**: no clean account-free drop-in.
  Common Voice is CC0 but **account-gated**; ReazonSpeech (JA) is account-gated
  **and** legally restricted (Article 30-4 information-analysis only). These
  need a logged-in manual fetch, not an automated account-free download.

## Standard English benchmark (the field's yardstick)

The de-facto English standard is the **Open ASR Leaderboard**, built on the
**ESB** benchmark of eight datasets — LibriSpeech (11h), Common Voice (27h),
VoxPopuli (5h), TED-LIUM (3h), GigaSpeech (40h), SPGISpeech (100h), Earnings-22
(5h), AMI (9h) — spanning audiobook / parliamentary / TED / podcast / financial /
meeting domains, ranked by **mean WER** (lower better). The current leaderboard
has expanded to ~11 datasets adding multilingual (CoVoST-2, FLEURS) + long-form
tracks. *(high confidence)*
Sources: [Open ASR Leaderboard](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard),
[ESB datasets](https://huggingface.co/datasets/esb/datasets),
[ESB paper](https://arxiv.org/abs/2210.13352), [leaderboard paper](https://arxiv.org/abs/2510.06961).

## Dataset license + access matrix

| Dataset | Lang | License | Account? | Download | GT format | Verdict for local corpus |
|---|---|---|---|---|---|---|
| **LibriSpeech** | en | CC BY 4.0 | **No** | OpenSLR /12 tarballs; HF `openslr/librispeech_asr` | per-utterance transcript text (`.trans.txt`) | ✅ **clean + account-free + small splits** |
| **AISHELL-1** | zh (Simplified) | Apache 2.0 | **No** | OpenSLR /33 (`data_aishell.tgz` ~15 GB) | transcript text | ✅ clean/account-free but ~15 GB single tgz, Simplified only |
| Common Voice (incl. zh-TW) | 300+ | CC0-1.0 | **Yes** (Mozilla Data Collective) | login + agree; MP3 + TSV | TSV/CSV sidecar | ⚠ license-clean but account-gated; version URLs go stale |
| ReazonSpeech | ja | CDLA-Sharing-1.0 (Art. 30-4) | **Yes** | HF, logged-in + accept | — | ⚠ account-gated **and** legally restricted |
| TED-LIUM | en | CC-BY-**NC**-ND-3.0 | No | HF/OpenSLR | STM | ⚠ non-commercial + no-derivatives — avoid |
| VoxPopuli | multi | CC0 | No | HF `facebook/voxpopuli` | — | ○ account-free CC0 (EU parliamentary) |
| Earnings-22 | en | CC-BY-SA-4.0 | No | rev.com github | — | ○ account-free, share-alike |
| GigaSpeech / SPGISpeech | en | Apache-2.0* / Kensho EULA | **Yes** | access form | — | ✗ account-gated |

*GigaSpeech's Apache-2.0 tag is community-contested against its non-commercial
audio terms — reinforcing its access-gated status. *(license/access rows: high confidence)*
Sources: [Open ASR Leaderboard card](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard),
[ESB datasets](https://huggingface.co/datasets/esb/datasets),
[LibriSpeech OpenSLR /12](https://www.openslr.org/12/),
[LibriSpeech HF](https://huggingface.co/datasets/openslr/librispeech_asr),
[AISHELL-1 paper](https://ar5iv.labs.arxiv.org/html/1709.05522), [OpenSLR /33](https://www.openslr.org/33/),
[Common Voice](https://github.com/common-voice/cv-dataset),
[ReazonSpeech](https://huggingface.co/datasets/reazon-research/reazonspeech).

### LibriSpeech specifics (the pick)
~1000h of 16 kHz read English from public-domain LibriVox audiobooks, CC BY 4.0,
no login. Eval splits: **dev-clean 5.4h (2703 utt)**, **test-clean 5.4h (2620 utt)**,
dev-other 5.3h (2864), test-other 5.1h (2939). Ground truth = plain transcript
text per utterance. *(high confidence)* —
[OpenSLR /12](https://www.openslr.org/12/), [HF card](https://huggingface.co/datasets/openslr/librispeech_asr),
[Panayotov et al. 2015](https://www.researchgate.net/publication/308871877_Librispeech_An_ASR_corpus_based_on_public_domain_audio_books).

## WER/CER methodology

The standard (Whisper convention, explicitly followed by SenseVoice) **normalizes
BOTH reference and hypothesis** before scoring, and uses **CER** for Chinese /
Cantonese / Japanese / Korean / Thai, **WER** for space-delimited languages.
*(high confidence)* — [SenseVoice paper](https://arxiv.org/pdf/2407.04051).

**Pitfall**: off-the-shelf normalizers (Whisper normalizer, also used by
MMS/Seamless) that strip "inconsistencies" in spelling/punctuation are flawed for
some scripts — for Indic scripts they strip vowel diacritics and collapse words to
consonants, artificially *improving* apparent accuracy. **Validate the normalizer
per-language** before trusting cross-dataset numbers. *(high confidence)* —
[arXiv 2409.02449](https://arxiv.org/abs/2409.02449). This corroborates bestASR's
existing zh-TW normalization care (#34: script-normalized Hant→Hans folding).

## SOTA open models (context for the model grid)

- **SenseVoice** (open, ModelScope/HF) — CJK-strong: SenseVoice-Small covers
  zh/yue/en/ja/ko (~300k h); beats Whisper-large-v3 in CER — AISHELL-1 test 2.96
  (Small) / 2.09 (Large) vs 5.14. Already in bestASR's grid (#50). *(high)* —
  [paper](https://arxiv.org/pdf/2407.04051), [HF](https://huggingface.co/FunAudioLLM/SenseVoiceSmall).
- **NVIDIA NeMo** — Parakeet-TDT-0.6B-v3 (25 European langs, CC-BY-4.0, ANE + MLX
  ports; already in bestASR #35) and Canary-1B-v2 (~978M, > Whisper-large-v3 on
  English at ~10x speed). **Neither covers Traditional Chinese or Japanese.**
  *(high)* — [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3),
  [Canary](https://huggingface.co/nvidia/canary-1b-v2).

## Actionable shortlist (license-clean, account-free, immediate download)

1. **LibriSpeech `test-clean`** — ~346 MB, CC BY 4.0, OpenSLR direct tarball, no
   account. The immediate pick; fills the English gap.
2. **LibriSpeech `dev-clean`** — ~337 MB, same terms. Natural second (dev/test pair).
3. *(optional, heavier)* AISHELL-1 — Simplified Mandarin, ~15 GB single tgz;
   account-free but large and not zh-TW.

**Not for automated download** (require login / restricted): Common Voice zh-TW,
ReazonSpeech (JA), TED-LIUM (NC-ND), GigaSpeech, SPGISpeech. zh-TW / JA corpus
expansion needs a separate logged-in manual-fetch path, tracked out of this issue.
