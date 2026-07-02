#!/bin/bash
# Fetch + register the standard corpora (#14 en; #18 zh/ja; spec corpora).
# - jfk.wav: whisper.cpp canonical sample (US-government speech, public domain)
# - OSR_us_000_0010: Open Speech Repository Harvard List 1 (free use)
# - FLEURS cmn_hans_cn / ja_jp: 3 dev-split utterances each, concatenated
#   (google/fleurs, CC-BY-4.0 — attribution: FLEURS, Google Research;
#   dataset revision pinned below per the #15 supply-chain discipline)
# Binaries are never committed; this script downloads, converts to 16 kHz mono
# where needed, verifies pinned SHA-256 digests, and registers via corpus add.
# zh/ja additionally need /usr/bin/python3 (Xcode CLT) for WAV concatenation.
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


# ── FLEURS zh/ja (#18) ────────────────────────────────────────────────────────
# Dataset revision pin (immutable content address for TSV + tars):
FLEURS_REV="70bb2e84b976b7e960aa89f1c648e09c59f894dd"
# TSV digests at that revision (auditability of the embedded ground truth: fetch
# data/<config>/dev.tsv at $FLEURS_REV, verify against these, and the embedded
# picks/transcripts below are greppable rows — derivation rule: first recording
# of the first three distinct sentence ids in TSV order):
#   cmn_hans_cn dev.tsv  6b4efd804b543048feb278db06f3b58b5ea171cdd4ba072e328ad630ca25384b
#   ja_jp       dev.tsv  92beded0999347ad5b8599fe70940e2e7b9232c67c426defb258e596ade94f48
# Raw-download pins — the tar bytes are verified BEFORE tar/afconvert parse them (#15):
FLEURS_ZH_TAR_SHA="3bc33212d5974eef7feb04bc4792458d6cd7e14ff10a1a24772f3c45ea87a822"
FLEURS_JA_TAR_SHA="2547f19203e1272aeba99c2235326fea525d6cfb9348bafbea2c3a7929e8e441"
# Pins of the CONVERTED, concatenated 16 kHz mono artifacts:
FLEURS_ZH_WAV_SHA="61a3ff2a7a6702c303b014aae60eea975f5458ab06215337a9342ed92d0a8832"
FLEURS_JA_WAV_SHA="9eb127b236b6af1598057a53c749b85ffebaa463b3d07c9ba329cff036ba257b"

# fetch_fleurs <config> <lang> <name> <tar_sha> <wav_sha> <picks (space-sep)> <srt heredoc via stdin>
fetch_fleurs() {
  local config="$1" lang="$2" name="$3" tar_sha="$4" wav_sha="$5" picks="$6"
  local wav="$DEST/fleurs_$lang.wav" srt="$DEST/fleurs_$lang.srt"
  local srt_body; srt_body=$(cat)   # ground truth embedded by the caller; written only after the wav verifies
  if [ ! -f "$wav" ]; then
    # Preflight BOTH toolchain deps before any 200MB download. Note: a bare
    # `command -v /usr/bin/python3` passes on the CLT-less macOS stub, so
    # actually execute it (imports the module the concat step needs).
    /usr/bin/python3 -c "import wave" >/dev/null 2>&1 \
      || { echo "✗ working /usr/bin/python3 required for WAV concatenation (install Xcode CLT)" >&2; return 1; }
    command -v afconvert >/dev/null \
      || { echo "✗ afconvert required (macOS CoreAudio) — cannot convert FLEURS float32 wavs" >&2; return 1; }
    local tmp; tmp=$(mktemp -d)
    # Any failure from here on cleans the ~200MB workspace (design D4).
    trap 'rm -rf "$tmp"' RETURN
    curl -fsSL --max-time 600 -o "$tmp/dev.tar.gz" \
      "https://huggingface.co/datasets/google/fleurs/resolve/$FLEURS_REV/data/$config/audio/dev.tar.gz"
    echo "$tar_sha  $tmp/dev.tar.gz" | shasum -a 256 -c - >/dev/null \
      || { echo "✗ raw FLEURS $config tar digest mismatch — refusing to parse" >&2; return 1; }
    local f
    for f in $picks; do
      tar -xzf "$tmp/dev.tar.gz" -C "$tmp" "dev/$f"
      afconvert -f WAVE -d LEI16@16000 -c 1 "$tmp/dev/$f" "$tmp/dev/${f%.wav}.pcm16.wav"
    done
    # Build into the workspace and mv into place ONLY after the digest verifies —
    # the final path never holds an unverified or truncated artifact, so an
    # interrupted or digest-failing run self-heals on retry instead of wedging
    # behind the [ ! -f ] guard.
    /usr/bin/python3 - "$tmp" "$tmp/concat.wav" $picks <<'PY'
import sys, wave, contextlib
tmp, out, picks = sys.argv[1], sys.argv[2], sys.argv[3:]
with wave.open(out, "wb") as w:
    for i, f in enumerate(picks):
        with contextlib.closing(wave.open(f"{tmp}/dev/{f[:-4]}.pcm16.wav", "rb")) as r:
            if i == 0: w.setparams(r.getparams())
            w.writeframes(r.readframes(r.getnframes()))
PY
    echo "$wav_sha  $tmp/concat.wav" | shasum -a 256 -c - >/dev/null \
      || { echo "✗ fleurs_$lang converted-artifact digest mismatch — likely afconvert/CoreAudio version drift on this host; nothing was registered (re-pin after inspecting: shasum -a 256 $tmp/concat.wav)" >&2; return 1; }
    mv "$tmp/concat.wav" "$wav"
  fi
  echo "$wav_sha  $wav" | shasum -a 256 -c - >/dev/null \
    || { echo "✗ fleurs_$lang.wav digest mismatch — remove it to rebuild: rm '$wav'" >&2; return 1; }
  printf '%s\n' "$srt_body" > "$srt"
  cat > "$DEST/fleurs_ATTRIBUTION.txt" <<'NOTICE'
FLEURS corpora (fleurs_zh.wav/.srt, fleurs_ja.wav/.srt) are built from the
FLEURS dataset (Google Research), CC-BY-4.0 — https://huggingface.co/datasets/google/fleurs
License: https://creativecommons.org/licenses/by/4.0/
Attribution must travel with any redistributed copy of these files.
NOTICE
  "$BIN" corpus add "$wav" "$srt" --language "$lang" --name "$name"
}

FETCH_FAILURES=0

run_fetch() {  # $1 = label; rest = command — isolate每個語料：一個失敗不擋其他（partial success）
  local label="$1"; shift
  if ! "$@"; then
    echo "⚠ $label skipped (see error above) — continuing with the remaining corpora" >&2
    FETCH_FAILURES=$((FETCH_FAILURES + 1))
  fi
}

fetch_fleurs_zh() { fetch_fleurs cmn_hans_cn zh fleurs-cmn-dev3 "$FLEURS_ZH_TAR_SHA" "$FLEURS_ZH_WAV_SHA" \
  "15119654797764315030.wav 6229499241916815991.wav 6873735086472854552.wav" <<'SRT'; }
1
00:00:00,000 --> 00:00:04,919
西班牙人开始了长达三个世纪的殖民时期。

2
00:00:04,919 --> 00:00:13,980
“我姐姐和她的朋友不见了，路上有两个残疾人坐着轮椅，有人跳过去帮他们推轮椅”，阿尔芒·范思哲说道。

3
00:00:13,980 --> 00:00:29,560
学生往往是最挑剔的读者，所以博客作者开始努力提高写作水平，避免受到批判。
SRT

fetch_fleurs_ja() { fetch_fleurs ja_jp ja fleurs-ja-dev3 "$FLEURS_JA_TAR_SHA" "$FLEURS_JA_WAV_SHA" \
  "11946010384058816161.wav 10411584430488337925.wav 3032699500128816119.wav" <<'SRT'; }
1
00:00:00,000 --> 00:00:16,739
場にふさわしい敬意を払い、尊厳と礼節をもって立ち振る舞ってください。ホロコーストやナチスについて冗談を言うなどもってのほかです。

2
00:00:16,739 --> 00:00:28,859
日本には約7,000の島々があり、その最大は本州列島で、世界で7番目に大きい島とされています。

3
00:00:28,859 --> 00:00:37,859
その後、ラッカ・シンが先頭に立ってバジャンを歌いました。
SRT

# en first (reliable, pre-existing) — the new FLEURS path can only ADD corpora,
# never gate them; every corpus is isolated so partial success is real (#18 verify).
run_fetch "jfk (en)"            fetch_jfk
run_fetch "osr-harvard-1 (en)"  fetch_osr
run_fetch "fleurs-cmn-dev3 (zh)" fetch_fleurs_zh
run_fetch "fleurs-ja-dev3 (ja)"  fetch_fleurs_ja
echo "✓ Standard corpora registered (en + zh + ja; failures above, if any, were skipped):"
"$BIN" corpus list
exit $((FETCH_FAILURES > 0 ? 1 : 0))
