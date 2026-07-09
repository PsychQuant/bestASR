## 1. Fetch pipeline — Requirement: LibriSpeech English standard-benchmark set is scriptable and verified

- [x] 1.1 Add a `fetch_librispeech` function to scripts/fetch-corpora.sh that downloads the LibriSpeech `test-clean` and `dev-clean` tarballs from OpenSLR and verifies each source tarball's pinned SHA-256 before extracting; a mismatch refuses to extract (fail-closed) and does not affect other languages. Verification: running the function with a corrupted tarball registers nothing for LibriSpeech; a clean run proceeds.
- [x] 1.2 Decode a deterministic pinned sample of utterances (~24 per split, 4 groups of 6) from FLAC to 16 kHz mono PCM16 via `ffmpeg -ar 16000 -ac 1 -c:a pcm_s16le -bitexact`, concatenate each group with the existing `concat_pcm16`, and verify each converted group artifact's pinned SHA-256 before registration (mismatch registers nothing for that group + reports). Verification: converted artifacts match their pinned digests on a clean run; a forced-different artifact is rejected.
- [x] 1.3 Emit a verbatim SRT per group (utterance transcripts in order, sequential timecodes from decoded clip durations) and register each group via `bestasr corpus add --language en` with a `librispeech-*` name. A missing ffmpeg is a loud error naming ffmpeg. Verification: `bestasr corpus list` shows the 3–5 LibriSpeech en corpora after a run.

## 2. Provenance pinning (real fetch run)

- [x] 2.1 Run the fetch once against the real OpenSLR tarballs to obtain the source tarball SHA-256 and the per-group converted-artifact SHA-256, and hardcode those pinned constants into the script. Verification: a second run passes all digest checks with no recompute needed.

## 3. References + verification

- [x] 3.1 Commit `references/asr-benchmark-landscape.md` (the adversarial-verified deep-research survey) as the durable cited basis for the dataset choice. Verification: the file exists and cites primary sources.
- [x] 3.2 End-to-end: run the LibriSpeech fetch step on this machine and confirm `bestasr corpus list` includes the LibriSpeech en corpora with verified hashes; the existing corpora and other languages are unaffected. Verification: `corpus list` output shows the new corpora alongside the existing set.
