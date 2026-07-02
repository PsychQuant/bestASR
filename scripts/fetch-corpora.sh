#!/bin/bash
# Fetch + register the English standard corpora (#14; spec corpora).
# - jfk.wav: whisper.cpp canonical sample (US-government speech, public domain)
# - OSR_us_000_0010: Open Speech Repository Harvard List 1 (free use)
# Binaries are never committed; this script downloads, converts to 16 kHz mono
# where needed, verifies pinned SHA-256 digests, and registers via corpus add.
set -euo pipefail

DEST="${BESTASR_CORPORA_DIR:-$HOME/.bestasr/corpora}"
BIN="${BESTASR_BIN:-bestasr}"
mkdir -p "$DEST"

# Pinned digests of the CONVERTED 16 kHz artifacts (jfk ships 16 kHz already).
JFK_SHA="59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e"
OSR_SHA="0ed4ea79ee09b36f40235992b5bc03009f23167c0525930ddeafee0c04716a49"

fetch_jfk() {
  local wav="$DEST/jfk.wav"
  [ -f "$wav" ] || curl -fsSL -o "$wav" \
    "https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/samples/jfk.wav"
  echo "$JFK_SHA  $wav" | shasum -a 256 -c - >/dev/null \
    || { echo "✗ jfk.wav digest mismatch — refusing to register" >&2; return 1; }
  cat > "$DEST/jfk.srt" <<'SRT'
1
00:00:00,000 --> 00:00:11,000
And so my fellow Americans, ask not what your country can do for you, ask what you can do for your country.
SRT
  "$BIN" corpus add "$wav" "$DEST/jfk.srt" --language en --name jfk
}

# Raw-download pin: the third-party bytes are verified BEFORE any parser
# (afconvert/CoreAudio) touches them (#15 — parse-before-verify gap).
OSR_RAW_SHA="a4bf9becd046d7aedb6d05b6e12347a6294a44f74d263089c636fb0a2b1e6561"

fetch_osr() {
  local raw="$DEST/osr10_8k.wav" wav="$DEST/osr10.wav"
  [ -f "$wav" ] || {
    curl -fsSL --max-time 120 -o "$raw" \
      "https://www.voiptroubleshooter.com/open_speech/american/OSR_us_000_0010_8k.wav"
    echo "$OSR_RAW_SHA  $raw" | shasum -a 256 -c - >/dev/null \
      || { echo "✗ raw OSR download digest mismatch — refusing to parse" >&2; rm -f "$raw"; return 1; }
    afconvert -f WAVE -d LEI16@16000 -c 1 "$raw" "$wav"
    rm -f "$raw"
  }
  echo "$OSR_SHA  $wav" | shasum -a 256 -c - >/dev/null \
    || { echo "✗ osr10.wav digest mismatch — refusing to register" >&2; return 1; }
  cat > "$DEST/osr10.srt" <<'SRT'
1
00:00:00,000 --> 00:00:33,000
The birch canoe slid on the smooth planks. Glue the sheet to the dark blue background. It's easy to tell the depth of a well. These days a chicken leg is a rare dish. Rice is often served in round bowls. The juice of lemons makes fine punch. The box was thrown beside the parked truck. The hogs were fed chopped corn and garbage. Four hours of steady work faced us. A large size in stockings is hard to sell.
SRT
  "$BIN" corpus add "$wav" "$DEST/osr10.srt" --language en --name osr-harvard-1
}

fetch_jfk
fetch_osr
echo "✓ English standard corpora registered:"
"$BIN" corpus list
