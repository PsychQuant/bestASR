## Context

`scripts/fetch-corpora.sh` already fetches, digest-verifies, converts, and
registers the standard corpora (JFK + OSR for en; FLEURS for ja; Common Voice for
zh-TW) following one pattern: download → verify source digest → convert to 16 kHz
mono PCM16 → `concat_pcm16` (python3 wave) → verify converted digest → write SRT →
`bestasr corpus add`. FLEURS/zh-TW use "24 utterances in 4 groups of 6". This
change adds LibriSpeech (the field's English yardstick, per
`references/asr-benchmark-landscape.md`) to that pipeline.

## Goals / Non-Goals

**Goals:**

- Register a small, representative LibriSpeech English corpus set (test-clean +
  dev-clean derived) through the existing digest-verified pipeline.
- Keep the supply chain pinned: source tarball digest + converted-artifact digest.
- Reuse the existing convention (medium-length grouped corpora, embedded SRT).

**Non-Goals:**

- Full-split download or per-utterance registration.
- New corpus-store schema, metric, or routing behavior.
- zh-TW / Japanese expansion (gated sources — separate issue).

## Decisions

**D1 — FLAC decode via ffmpeg, bit-exact.** LibriSpeech ships FLAC; `afconvert`
(used for the MP3 sources) does not read FLAC. Decode with
`ffmpeg -i clip.flac -ar 16000 -ac 1 -c:a pcm_s16le -bitexact <out>.wav`. The
`-bitexact` flag suppresses ffmpeg's encoder/metadata chunks so the converted WAV
is deterministic across runs, which is what makes the converted-artifact digest a
stable pin (the same fragility the existing script accepts for afconvert drift,
minimized here).

**D2 — Pin the source tarball digest, not just the converted output.** OpenSLR
serves stable tarballs (`test-clean.tar.gz`, `dev-clean.tar.gz`) with published
digests; verifying the tarball before decode is the strongest provenance anchor.
The converted-group digests are pinned too (integrity + drift detection), matching
the existing pattern.

**D3 — Deterministic sample, ~24 utterances in 4 groups of 6, per split.** From
each split's extracted tree, select a fixed, sorted list of utterance ids (pinned
in the script) so the sample is reproducible. Concatenate each group's FLAC-decoded
WAVs; the SRT cues are the utterances in order with sequential timecodes computed
from each clip's decoded duration. LibriSpeech ground truth is uppercase, no
punctuation — used verbatim as the cue text (the benchmark normalizer folds case).

**D4 — Provenance/pinning computed by a real fetch run.** The pinned source and
converted digests can only be obtained by running the fetch once against the real
OpenSLR tarballs; those values are then hardcoded into the script (chicken-and-egg
resolved by the apply step actually downloading + converting once).

## Implementation Contract

**Behavior:** running `scripts/fetch-corpora.sh` (LibriSpeech step) on a
network-connected machine downloads the two OpenSLR tarballs, verifies their
pinned digests, decodes the pinned utterance sample from FLAC, concatenates into
8 corpora (4 per split) with embedded SRT, verifies converted digests, and registers each via
`bestasr corpus add --language en`. `bestasr corpus list` then shows the new
LibriSpeech corpora. A digest mismatch (source or converted) registers nothing for
the affected group and reports the mismatch (fail-closed); other languages are
unaffected.

**Interface / data shape:** a new `fetch_librispeech` shell function + pinned
constants (source tarball URLs + SHA-256, per-group utterance-id picks, per-group
converted SHA-256). Corpus names follow the existing convention, e.g.
`librispeech-testclean-1..N` / `librispeech-devclean-1..N`, language `en`.

**Failure modes:** missing ffmpeg → loud error naming ffmpeg (like the existing
python3 check); source digest mismatch → refuse extract; converted digest
mismatch → register nothing for that group + report.

**Acceptance criteria:** after the fetch run, `bestasr corpus list` includes the
LibriSpeech en corpora; a `scripts/tests`-style shell check (or manual assertion)
confirms the corpora registered with verified hashes; `references/asr-benchmark-landscape.md`
exists as the cited basis.

**Scope boundaries:** in scope — `scripts/fetch-corpora.sh` (add function +
pinned constants), `references/asr-benchmark-landscape.md`. Out of scope — corpus
store schema, metrics, routing, zh-TW/JA, the full splits.

## Risks / Trade-offs

- **ffmpeg version drift** could change the converted-artifact bytes and trip the
  pinned digest; `-bitexact` minimizes this, and the source-tarball pin is the
  durable anchor. On mismatch the group fails closed (no silent drift).
- **Download size** — the two tarballs are ~683 MB total; only a sample is used,
  but the tarball is the OpenSLR download unit. Audio is never committed.
- **Reproducibility of the sample** depends on the pinned utterance-id list; if a
  future OpenSLR re-release changed the tree, the source-digest pin would catch it.
