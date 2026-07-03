#!/bin/bash
# Reproducible acoustic validation for #25 speaker diarization (design D5).
# Builds the guaranteed two-speaker fixture — the SAME FLEURS sentence (id 1566)
# recorded by a male and a female speaker, definitionally distinct voices, with
# ONE SECOND OF SILENCE between them: cue-level assignment (design D1) can only
# show a speaker change where transcription breaks a segment, and the silence
# guarantees that break at the boundary (real speaker handovers usually pause;
# the fixture just makes it deterministic). Full #15/#18 pinning discipline.
# Asserts:
#   1. two distinct SPEAKER_N labels appear;
#   2. the label switch lands within ±2s of the 9.30s concatenation boundary;
#   3. single-speaker jfk yields exactly one label (negative control);
#   4. the same run WITHOUT --diarize emits no SPEAKER strings.
# Requires: network on first run (FLEURS tar ~171MB + CoreML models), afconvert,
# /usr/bin/python3 (Xcode CLT). Attribution: FLEURS (Google Research), CC-BY-4.0.
set -euo pipefail

BIN="${BESTASR_BIN:-bestasr}"
WORK="${BESTASR_VALIDATE_DIR:-$HOME/.bestasr/validate}"
mkdir -p "$WORK"

FLEURS_REV="70bb2e84b976b7e960aa89f1c648e09c59f894dd"
JA_TAR_SHA="2547f19203e1272aeba99c2235326fea525d6cfb9348bafbea2c3a7929e8e441"
FIXTURE_SHA="5c29dfde021497bc1f0158c4d1d21c9beca05569327dcb987d79d674dabe01d4"
PICK_MALE="3502985659381719550.wav"     # sentence 1566, MALE
PICK_FEMALE="5510872108388823452.wav"   # sentence 1566, FEMALE
BOUNDARY=9.30   # end of the male utterance; the female cue starts ~10.30 (after the 1s gap) — ±2s tolerance covers

FIXTURE="$WORK/twospeaker_ja.wav"
if [ ! -f "$FIXTURE" ]; then
  /usr/bin/python3 -c "import wave" >/dev/null 2>&1 \
    || { echo "✗ working /usr/bin/python3 required (Xcode CLT)" >&2; exit 1; }
  command -v afconvert >/dev/null || { echo "✗ afconvert required" >&2; exit 1; }
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --max-time 600 -o "$tmp/dev.tar.gz" \
    "https://huggingface.co/datasets/google/fleurs/resolve/$FLEURS_REV/data/ja_jp/audio/dev.tar.gz"
  echo "$JA_TAR_SHA  $tmp/dev.tar.gz" | shasum -a 256 -c - >/dev/null \
    || { echo "✗ raw tar digest mismatch — refusing to parse" >&2; exit 1; }
  for f in "$PICK_MALE" "$PICK_FEMALE"; do
    tar -xzf "$tmp/dev.tar.gz" -C "$tmp" "dev/$f"
    afconvert -f WAVE -d LEI16@16000 -c 1 "$tmp/dev/$f" "$tmp/dev/${f%.wav}.pcm16.wav"
  done
  /usr/bin/python3 - "$tmp" "$tmp/concat.wav" "$PICK_MALE" "$PICK_FEMALE" <<'PY'
import sys, wave, contextlib
tmp, out, picks = sys.argv[1], sys.argv[2], sys.argv[3:]
with wave.open(out, "wb") as w:
    for i, f in enumerate(picks):
        with contextlib.closing(wave.open(f"{tmp}/dev/{f[:-4]}.pcm16.wav", "rb")) as r:
            if i == 0:
                w.setparams(r.getparams())
            else:
                w.writeframes(b"\x00\x00" * 16000)  # 1.0s silence — deterministic segment break
            w.writeframes(r.readframes(r.getnframes()))
PY
  echo "$FIXTURE_SHA  $tmp/concat.wav" | shasum -a 256 -c - >/dev/null \
    || { echo "✗ fixture digest mismatch (afconvert drift? re-pin after inspection)" >&2; exit 1; }
  mv "$tmp/concat.wav" "$FIXTURE"
fi
echo "$FIXTURE_SHA  $FIXTURE" | shasum -a 256 -c - >/dev/null

# ── 1+2: two speakers, switch near the boundary ──
"$BIN" transcribe "$FIXTURE" --model large-v3-turbo --language ja \
  --format srt --output "$WORK/twospk.srt" --diarize >/dev/null
DISTINCT=$(grep -oE '\[SPEAKER_[0-9]+\]' "$WORK/twospk.srt" | sort -u | wc -l | tr -d ' ')
[ "$DISTINCT" -ge 2 ] || { echo "✗ expected ≥2 distinct speakers, got $DISTINCT"; cat "$WORK/twospk.srt"; exit 1; }
SWITCH=$(/usr/bin/python3 - "$WORK/twospk.srt" <<'PY'
import re, sys
cues = re.findall(r"(\d\d):(\d\d):(\d\d),(\d\d\d) --> .*\n\[(SPEAKER_\d+)\]", open(sys.argv[1]).read())
prev = None
for h, m, s, ms, spk in cues:
    t = int(h)*3600 + int(m)*60 + int(s) + int(ms)/1000
    if prev and spk != prev: print(f"{t:.2f}"); break
    prev = spk
PY
)
[ -n "$SWITCH" ] || { echo "✗ no speaker switch found"; exit 1; }
DIFF=$(/usr/bin/python3 -c "print(abs($SWITCH - $BOUNDARY))")
/usr/bin/python3 -c "exit(0 if $DIFF <= 2.0 else 1)" \
  || { echo "✗ switch at ${SWITCH}s, expected ≈${BOUNDARY}s (±2s)"; exit 1; }
echo "✓ two speakers, switch at ${SWITCH}s (boundary ${BOUNDARY}s)"

# ── 3: negative control ──
JFK="${BESTASR_CORPORA_DIR:-$HOME/.bestasr/corpora}/jfk.wav"
if [ -f "$JFK" ]; then
  "$BIN" transcribe "$JFK" --model large-v3-turbo --language en \
    --format srt --output "$WORK/jfk.srt" --diarize >/dev/null
  N=$(grep -oE '\[SPEAKER_[0-9]+\]' "$WORK/jfk.srt" | sort -u | wc -l | tr -d ' ')
  [ "$N" = "1" ] || { echo "✗ jfk negative control: expected 1 speaker, got $N"; exit 1; }
  echo "✓ jfk single-speaker control"
else
  echo "⚠ jfk.wav not registered — skipping negative control (run scripts/fetch-corpora.sh)"
fi

# ── 4: off means clean ──
"$BIN" transcribe "$FIXTURE" --model large-v3-turbo --language ja \
  --format srt --output "$WORK/plain.srt" >/dev/null
grep -q "SPEAKER" "$WORK/plain.srt" && { echo "✗ no-diarize output contains SPEAKER"; exit 1; }
echo "✓ no-diarize output clean"
echo "✓ diarization validation passed"
