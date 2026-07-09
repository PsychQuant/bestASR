## Why

bestASR's English benchmark corpus is thin (a public-domain JFK clip + OSR
Harvard samples). A `/deep-research` survey of the ASR evaluation landscape
(2026-07-09, adversarial-verified, see `references/asr-benchmark-landscape.md`)
found that **LibriSpeech** is the field's de-facto English yardstick and the
single strongest license-clean, account-free corpus: ~1000h of 16 kHz read
English from public-domain LibriVox, CC BY 4.0, downloadable without an account
from OpenSLR, with small dev/test splits. Adding a LibriSpeech-derived corpus
makes bestASR's English routing measured against the standard the whole field
reports on. (The survey also confirmed the Traditional-Chinese and Japanese
account-free options are gated/restricted, so this change is English-only;
zh-TW/JA expansion is tracked separately.)

## What Changes

- Extend `scripts/fetch-corpora.sh` with a `fetch_librispeech` function that
  downloads the LibriSpeech `test-clean` and `dev-clean` tarballs from OpenSLR,
  verifies pinned source digests, decodes a deterministic sample of utterances
  from FLAC to 16 kHz mono PCM16 (via ffmpeg, bit-exact), concatenates them into
  a few medium-length corpora with an embedded verbatim SRT reference, verifies
  the converted-artifact digests, and registers them via `bestasr corpus add
  --language en`.
- Following the established English-set convention: 24 utterances per split
  (4 groups of 6), i.e. 8 corpora / 48 utterances across `test-clean` +
  `dev-clean`, so per-corpus CER/WER can be averaged and variance observed.
  Binaries are never committed (audio lands under `~/.bestasr/corpora`).
- Add `references/asr-benchmark-landscape.md` as the durable literature base that
  motivated the dataset choice.

## Non-Goals

- Downloading the full LibriSpeech splits or registering thousands of
  per-utterance corpora (the convention is a small representative sample, not the
  whole dataset).
- Traditional-Chinese (zh-TW) or Japanese corpus expansion — the account-free
  options are gated/restricted (Common Voice login-gated, ReazonSpeech Article
  30-4 restricted); tracked out of this change.
- Changing the benchmark metric, routing, or corpus-store schema — this only adds
  registered corpora through the existing `corpus add` path.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `corpora`: adds a LibriSpeech English standard-benchmark set to the scriptable,
  digest-verified fetch pipeline.

## Impact

- Affected specs: `corpora` (ADDED requirement for the LibriSpeech English set)
- Affected code:
  - Modified: scripts/fetch-corpora.sh
  - New: references/asr-benchmark-landscape.md
