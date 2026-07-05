#!/bin/bash
# Fetch + register the standard corpora (#14 en; #18 ja; #34 zh-TW + scale-out; spec corpora).
# - jfk.wav: whisper.cpp canonical sample (US-government speech, public domain)
# - OSR_us_000_0010/0011/0012: Open Speech Repository Harvard Lists 1-3 (free use)
# - FLEURS ja_jp: 24 dev-split utterances in 4 groups of 6, concatenated
#   (google/fleurs, CC-BY-4.0 — attribution: FLEURS, Google Research)
# - Common Voice zh-TW (#34): 24 clips in 4 groups of 6 — TRADITIONAL Chinese
#   (Taiwanese Mandarin), CC-0. Fetched from the fsicoli HF mirror at a pinned
#   revision (the official channel moved to Mozilla Data Collective login-only
#   in Oct 2025; the mirror is third-party — every byte is digest-verified, see
#   design D3 provenance caveat). Simplified Chinese is NOT part of the set (#34).
# Binaries are never committed; this script downloads, converts to 16 kHz mono
# where needed, verifies pinned SHA-256 digests, and registers via corpus add.
# zh-TW/ja additionally need /usr/bin/python3 (Xcode CLT) for WAV concatenation.
set -euo pipefail

DEST="${BESTASR_CORPORA_DIR:-$HOME/.bestasr/corpora}"
BIN="${BESTASR_BIN:-bestasr}"
mkdir -p "$DEST"

# Pinned digests of the CONVERTED 16 kHz artifacts (jfk ships 16 kHz already).
JFK_SHA="59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e"

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

# ── OSR Harvard lists (en) ────────────────────────────────────────────────────
# Raw-download pins: third-party bytes are verified BEFORE any parser
# (afconvert/CoreAudio) touches them (#15 — parse-before-verify gap).
# Ground truth = the published Harvard sentence lists (recordings are standard
# readings of them; mapping ASR-verified at pin time, #34).
OSR1_RAW_SHA="a4bf9becd046d7aedb6d05b6e12347a6294a44f74d263089c636fb0a2b1e6561"
OSR1_SHA="0ed4ea79ee09b36f40235992b5bc03009f23167c0525930ddeafee0c04716a49"
OSR2_RAW_SHA="3b3b791dc1eda4ed9ae7869c6adff95cbd9a0a4b0f45e31be31324024279b739"
OSR2_SHA="3e69e65c8b543d197d9e1cbe9f20d631c143060e89d16595c82bb316456e1bef"
OSR3_RAW_SHA="68c2cb1c146119c12b06a209665d17bb310c4e780dd19313bdca2d03b633878e"
OSR3_SHA="26c9f26014ac7ff92af237dfde1e23bd29fc3fcc0fc9d2a35c8f55110d52f9da"

# fetch_osr_list <file-num> <name> <raw_sha> <wav_sha>  (SRT body via stdin)
fetch_osr_list() {
  local num="$1" name="$2" raw_sha="$3" wav_sha="$4"
  local raw="$DEST/${name}_8k.wav" wav="$DEST/${name}.wav" srt_body
  srt_body=$(cat)
  if [ ! -f "$wav" ]; then
    curl -fsSL --max-time 120 -o "$raw" \
      "https://www.voiptroubleshooter.com/open_speech/american/OSR_us_000_${num}_8k.wav"
    echo "$raw_sha  $raw" | shasum -a 256 -c - >/dev/null \
      || { echo "✗ raw OSR $num download digest mismatch — refusing to parse" >&2; rm -f "$raw"; return 1; }
    afconvert -f WAVE -d LEI16@16000 -c 1 "$raw" "$wav"
    rm -f "$raw"
  fi
  echo "$wav_sha  $wav" | shasum -a 256 -c - >/dev/null \
    || { echo "✗ ${name}.wav digest mismatch — refusing to register" >&2; return 1; }
  printf '%s\n' "$srt_body" > "$DEST/${name}.srt"
  "$BIN" corpus add "$wav" "$DEST/${name}.srt" --language en --name "$name"
}

fetch_osr1() { fetch_osr_list 0010 osr-harvard-1 "$OSR1_RAW_SHA" "$OSR1_SHA" <<'SRT'; }
1
00:00:00,000 --> 00:00:33,000
The birch canoe slid on the smooth planks. Glue the sheet to the dark blue background. It's easy to tell the depth of a well. These days a chicken leg is a rare dish. Rice is often served in round bowls. The juice of lemons makes fine punch. The box was thrown beside the parked truck. The hogs were fed chopped corn and garbage. Four hours of steady work faced us. A large size in stockings is hard to sell.
SRT

fetch_osr2() { fetch_osr_list 0011 osr-harvard-2 "$OSR2_RAW_SHA" "$OSR2_SHA" <<'SRT'; }
1
00:00:00,000 --> 00:00:32,800
The boy was there when the sun rose. A rod is used to catch pink salmon. The source of the huge river is the clear spring. Kick the ball straight and follow through. Help the woman get back to her feet. A pot of tea helps to pass the evening. Smoky fires lack flame and heat. The soft cushion broke the man's fall. The salt breeze came across from the sea. The girl at the booth sold fifty bonds.
SRT

fetch_osr3() { fetch_osr_list 0012 osr-harvard-3 "$OSR3_RAW_SHA" "$OSR3_SHA" <<'SRT'; }
1
00:00:00,000 --> 00:00:33,300
The small pup gnawed a hole in the sock. The fish twisted and turned on the bent hook. Press the pants and sew a button on the vest. The swan dive was far short of perfect. The beauty of the view stunned the young boy. Two blue fish swam in the tank. Her purse was full of useless trash. The colt reared and threw the tall rider. It snowed, rained, and hailed the same morning. Read verse out loud for pleasure.
SRT

# ── FLEURS ja (#18 → #34 scale-out: 24 utterances, 4 groups of 6) ─────────────
# Dataset revision pin (immutable content address for TSV + tar):
FLEURS_REV="70bb2e84b976b7e960aa89f1c648e09c59f894dd"
# ja_jp dev.tsv digest at that revision (auditability of the embedded ground
# truth): 92beded0999347ad5b8599fe70940e2e7b9232c67c426defb258e596ade94f48
# Derivation rule for the picks: first recording of the first 24 distinct
# sentence ids in TSV order, split into 4 groups of 6 in that order (#34).
FLEURS_JA_TAR_SHA="2547f19203e1272aeba99c2235326fea525d6cfb9348bafbea2c3a7929e8e441"
FLEURS_JA_G1_SHA="3a6b87c746722c51d010d9becbd924dfb2735441aa1bd75fb71c781c1bbb2eac"
FLEURS_JA_G2_SHA="b291e769586cf78df4eeda60545eeecbb442aa690a29ea8e43a8f73d5e729c80"
FLEURS_JA_G3_SHA="4323b9fa96de7893e096b05e1e7eeb42e4d374139e5220402a35eac1e004e613"
FLEURS_JA_G4_SHA="f4b31295ca43a86cccb6c27ea5d4e803b61c873340165b8b8403df1233f7fd71"
JA_PICKS_1="11946010384058816161.wav 10411584430488337925.wav 3032699500128816119.wav 11052728666022746352.wav 5737391341571244470.wav 2174355903231001034.wav"
JA_PICKS_2="6966244244941274896.wav 4781525126910759634.wav 12090560248408007785.wav 17537571717853900648.wav 6510904302662524830.wav 15304202345218163846.wav"
JA_PICKS_3="17468873847526062022.wav 7382461951706957035.wav 14844643323670520228.wav 7627342719880580641.wav 7656613669272340700.wav 9633305044980004895.wav"
JA_PICKS_4="11452130507990569418.wav 15315349494137115815.wav 4094665828851158897.wav 1549811398684196073.wav 7316372300104839561.wav 16805800775879847417.wav"

fleurs_ja_group_sha() {
  case "$1" in
    1) echo "$FLEURS_JA_G1_SHA" ;;  2) echo "$FLEURS_JA_G2_SHA" ;;
    3) echo "$FLEURS_JA_G3_SHA" ;;  4) echo "$FLEURS_JA_G4_SHA" ;;
  esac
}
fleurs_ja_group_picks() {
  case "$1" in
    1) echo "$JA_PICKS_1" ;;  2) echo "$JA_PICKS_2" ;;
    3) echo "$JA_PICKS_3" ;;  4) echo "$JA_PICKS_4" ;;
  esac
}

# concat_pcm16 <dir> <out.wav> <picks...> — python3 wave concat (pcm16 only)
concat_pcm16() {
  /usr/bin/python3 - "$@" <<'PY'
import sys, wave, contextlib
d, out, picks = sys.argv[1], sys.argv[2], sys.argv[3:]
with wave.open(out, "wb") as w:
    for i, f in enumerate(picks):
        with contextlib.closing(wave.open(f"{d}/{f}", "rb")) as r:
            if i == 0: w.setparams(r.getparams())
            w.writeframes(r.readframes(r.getnframes()))
PY
}

preflight_concat_tools() {
  /usr/bin/python3 -c "import wave" >/dev/null 2>&1 \
    || { echo "✗ working /usr/bin/python3 required for WAV concatenation (install Xcode CLT)" >&2; return 1; }
  command -v afconvert >/dev/null \
    || { echo "✗ afconvert required (macOS CoreAudio)" >&2; return 1; }
}

fetch_fleurs_ja() {
  local need=0 gi
  for gi in 1 2 3 4; do [ -f "$DEST/fleurs-ja-$gi.wav" ] || need=1; done
  if [ "$need" = 1 ]; then
    preflight_concat_tools || return 1
    local tmp; tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"; trap - RETURN' RETURN  # self-clearing — a leaked RETURN trap re-fires on the NEXT function return with $tmp out of scope (set -u kill, #34)
    curl -fsSL --max-time 600 -o "$tmp/dev.tar.gz" \
      "https://huggingface.co/datasets/google/fleurs/resolve/$FLEURS_REV/data/ja_jp/audio/dev.tar.gz"
    echo "$FLEURS_JA_TAR_SHA  $tmp/dev.tar.gz" | shasum -a 256 -c - >/dev/null \
      || { echo "✗ raw FLEURS ja tar digest mismatch — refusing to parse" >&2; return 1; }
    local f picks converted
    for gi in 1 2 3 4; do
      picks=$(fleurs_ja_group_picks "$gi")
      converted=""
      for f in $picks; do
        tar -xzf "$tmp/dev.tar.gz" -C "$tmp" "dev/$f"
        afconvert -f WAVE -d LEI16@16000 -c 1 "$tmp/dev/$f" "$tmp/dev/${f%.wav}.pcm16.wav"
        converted="$converted ${f%.wav}.pcm16.wav"
      done
      concat_pcm16 "$tmp/dev" "$tmp/fleurs-ja-$gi.wav" $converted
      echo "$(fleurs_ja_group_sha "$gi")  $tmp/fleurs-ja-$gi.wav" | shasum -a 256 -c - >/dev/null \
        || { echo "✗ fleurs-ja-$gi converted-artifact digest mismatch — likely afconvert/CoreAudio drift; nothing registered for this group" >&2; return 1; }
      mv "$tmp/fleurs-ja-$gi.wav" "$DEST/fleurs-ja-$gi.wav"
    done
  fi
  for gi in 1 2 3 4; do
    echo "$(fleurs_ja_group_sha "$gi")  $DEST/fleurs-ja-$gi.wav" | shasum -a 256 -c - >/dev/null \
      || { echo "✗ fleurs-ja-$gi.wav digest mismatch — remove it to rebuild" >&2; return 1; }
  done
  cat > "$DEST/fleurs_ATTRIBUTION.txt" <<'NOTICE'
FLEURS corpora (fleurs-ja-1..4 .wav/.srt) are built from the FLEURS dataset
(Google Research), CC-BY-4.0 — https://huggingface.co/datasets/google/fleurs
License: https://creativecommons.org/licenses/by/4.0/
Attribution must travel with any redistributed copy of these files.
NOTICE
  write_fleurs_ja_srts
  for gi in 1 2 3 4; do
    "$BIN" corpus add "$DEST/fleurs-ja-$gi.wav" "$DEST/fleurs-ja-$gi.srt" --language ja --name "fleurs-ja-$gi"
  done
}

write_fleurs_ja_srts() {
  cat > "$DEST/fleurs-ja-1.srt" <<'SRT'
1
00:00:00,000 --> 00:00:16,740
場にふさわしい敬意を払い、尊厳と礼節をもって立ち振る舞ってください。ホロコーストやナチスについて冗談を言うなどもってのほかです。

2
00:00:16,740 --> 00:00:28,860
日本には約7,000の島々があり、その最大は本州列島で、世界で7番目に大きい島とされています。

3
00:00:28,860 --> 00:00:37,860
その後、ラッカ・シンが先頭に立ってバジャンを歌いました。

4
00:00:37,860 --> 00:00:47,460
自然主義者や哲学者たちは、古典書、特にラテン語で書かれた聖書に注目していました。

5
00:00:47,460 --> 00:01:03,780
最初のレースはスラロームでしたが、彼女は最初の滑走でリタイア（Did Not Finish）となりました。このレースでは116人の選手のうち36人が同じ結果となりました。

6
00:01:03,780 --> 00:01:24,660
メキシコのアーリー・ベラスケスは、男子シッティングスーパーGで15位に終わりました。ニュージーランドのアダム・ホールは、男子スタンディング・スーパーGで9位に入賞しました。
SRT
  cat > "$DEST/fleurs-ja-2.srt" <<'SRT'
1
00:00:00,000 --> 00:00:09,240
ここは火曜日に伐採される予定だったが、裁判所による緊急判決によって救われました。

2
00:00:09,240 --> 00:00:22,860
提示された見解は、他の場所で入手可能なより詳細な情報に比べて、大雑把で単純化されすぎた上っ面だけのものが多い。

3
00:00:22,860 --> 00:00:34,620
当初の装いは東方のビザンチン文化の影響を強く受けたものでした。

4
00:00:34,620 --> 00:00:45,000
新王国の古代エジプト人たちは、当時千年以上前に建てられた前身のモニュメントに驚嘆しました。

5
00:00:45,000 --> 00:00:58,740
しかし、カタルーニャ語が第一公用語として法律で定められているため、ほとんどの標識がカタルーニャ語のみで表示されています。

6
00:00:58,740 --> 00:01:12,360
.科学者によると、この動物の羽毛は外側が栗色で内側が暖色系の色でした。
SRT
  cat > "$DEST/fleurs-ja-3.srt" <<'SRT'
1
00:00:00,000 --> 00:00:06,600
彼はWi-Fiで鳴るドアベルを作ったそうです。

2
00:00:06,600 --> 00:00:26,160
クルーガー国立公園（KNP）は、南アフリカの北東部に位置し、東はモザンビーク、北はジンバブエとの国境に沿って走り、南の国境はクロコダイル川になっています。

3
00:00:26,160 --> 00:00:42,780
まもなく暴動鎮圧用の装備を着用した警官たちが収容所に入り、催涙ガスで受刑者を追い詰めました。

4
00:00:42,780 --> 00:00:57,000
女性は文化の違いはハラスメントと呼ばれる行為にながりうることを女性は認識しておくべきであり、尾行されたり、腕を掴まれたりするのは珍しくありません。

5
00:00:57,000 --> 00:01:15,360
技術は、仮想社会科見学による学習方法を提供します。生徒たちは、教室に居ながらにして、博物館の工芸品を見たり、水族館を訪れたり、美しい芸術を鑑賞したりできます。

6
00:01:15,360 --> 00:01:24,240
州間の税法や関税を無効にする権限もありませんでした。
SRT
  cat > "$DEST/fleurs-ja-4.srt" <<'SRT'
1
00:00:00,000 --> 00:00:17,280
メートル法の採用、絶対主義から共和主義への移行、愛国心、そして国は単独支配者ではなく国民のものであるという信念など、多くの社会的政治的影響がありました。

2
00:00:17,280 --> 00:00:31,260
ニュート・ジングリッチ元下院議長、リック・ペリーテキサス州知事、ミケーレ・バックマン下院議員がそれぞれ4位、5位、6位に入りました。

3
00:00:31,260 --> 00:00:45,960
また、国連では、地球温暖化の影響を被っている国々がその影響に対処できるように支援するための基金について最終決定したいと考えています。

4
00:00:45,960 --> 00:01:03,060
警告の内容は、現時点でイラクでどのような行動をとっても、宗派間抗争や暴力の拡大、あるいは混沌への滑落を阻止しうると保証できる者はいないというものでした。

5
00:01:03,060 --> 00:01:15,960
ほとんどの地区には日本製のコースターバスが運行し、いずれも快適で頑丈な小型バスです。

6
00:01:15,960 --> 00:01:36,780
RingのCEOであるジェイミー・スミノフは以前に、玄関の呼び出し音がガレージにある自分店から聞こえなかったことから事業を始めたと述べました。
SRT
}

# ── Common Voice zh-TW (#34): TRADITIONAL Chinese, 24 clips, 4 groups of 6 ────
# Channel: fsicoli/common_voice_17_0 HF mirror at a pinned revision. The
# official channel is Mozilla Data Collective (login-only) since Oct 2025 and
# the mozilla-foundation HF repos were emptied; the mirror is third-party, so
# every byte is digest-verified below (revision + shard tar + per-clip +
# converted artifacts). Provenance-maximal alternative: download the official
# zh-TW tarball from Data Collective yourself and place the selected clips at
# $tmp — the per-clip digests below still verify them (design D3).
# License: CC-0 (public domain dedication) — https://commonvoice.mozilla.org
CV_ZHTW_REV="8262c16bf297c87a9cd88c51997c4758ed7a8ba2"
CV_ZHTW_TAR_SHA="dd75cfd240e3ee3be7a8a755417a7a02077d449a57a2f8be23b811d6179c3d32"
CV_ZHTW_G1_SHA="33dd468f27c641805bf6ddf6582a5ba9a21313df03e9ef14cffb71148c247c28"
CV_ZHTW_G2_SHA="af3571b78130940bf2c5c4d98a5767ef71a377a211c8e6d4728a90de3c856e39"
CV_ZHTW_G3_SHA="d6dc44a1f5f89a28938177d69077cbaacf76a0951062575bc40b7ebf26faaa3c"
CV_ZHTW_G4_SHA="29007d2e6418b96cb21ed9f3edd4f429c9c6c59d734d4eb84589e12234f5330f"
ZHTW_PICKS_1="common_voice_zh-TW_20434124.mp3 common_voice_zh-TW_31336528.mp3 common_voice_zh-TW_36757474.mp3 common_voice_zh-TW_31018677.mp3 common_voice_zh-TW_17880834.mp3 common_voice_zh-TW_17396052.mp3"
ZHTW_PICKS_2="common_voice_zh-TW_19516543.mp3 common_voice_zh-TW_20964151.mp3 common_voice_zh-TW_31113143.mp3 common_voice_zh-TW_25016944.mp3 common_voice_zh-TW_17380171.mp3 common_voice_zh-TW_26931726.mp3"
ZHTW_PICKS_3="common_voice_zh-TW_19739280.mp3 common_voice_zh-TW_22053420.mp3 common_voice_zh-TW_23377180.mp3 common_voice_zh-TW_26992639.mp3 common_voice_zh-TW_17383515.mp3 common_voice_zh-TW_18669890.mp3"
ZHTW_PICKS_4="common_voice_zh-TW_19506878.mp3 common_voice_zh-TW_17413347.mp3 common_voice_zh-TW_32240866.mp3 common_voice_zh-TW_22426352.mp3 common_voice_zh-TW_18744205.mp3 common_voice_zh-TW_32158843.mp3"

cv_zhtw_group_sha() {
  case "$1" in
    1) echo "$CV_ZHTW_G1_SHA" ;;  2) echo "$CV_ZHTW_G2_SHA" ;;
    3) echo "$CV_ZHTW_G3_SHA" ;;  4) echo "$CV_ZHTW_G4_SHA" ;;
  esac
}
cv_zhtw_group_picks() {
  case "$1" in
    1) echo "$ZHTW_PICKS_1" ;;  2) echo "$ZHTW_PICKS_2" ;;
    3) echo "$ZHTW_PICKS_3" ;;  4) echo "$ZHTW_PICKS_4" ;;
  esac
}

verify_zhtw_clips() {  # $1 = tmp dir; per-clip pins — mirror bytes are untrusted (#34)
  local tmp="$1"
  shasum -a 256 -c - >/dev/null <<CLIPSHA
c4cbe381bb7aa4b803110effbc88b643e2bd0a6b8ddc71e5cf04beb0db9613ba  $tmp/zh-TW_dev_0/common_voice_zh-TW_20434124.mp3
8ed4edb3757be0a241ba147d9c64221d5ad13cdaba3b0012b78218669fd0ad4a  $tmp/zh-TW_dev_0/common_voice_zh-TW_31336528.mp3
4c56aa9d9aafba4614efe8408ab76892442b467aa5ede1ed52dd6d7034b482bd  $tmp/zh-TW_dev_0/common_voice_zh-TW_36757474.mp3
181d6d7edd87d755dc0f53955b71218b727b0409a6f59d29955ff036e35bdd72  $tmp/zh-TW_dev_0/common_voice_zh-TW_31018677.mp3
f89d9a217e3a85ac36e4eaeadce6c68fc17323cb8dfd5d60591f706b539d5fd9  $tmp/zh-TW_dev_0/common_voice_zh-TW_17880834.mp3
8dc8230af83d31850212ffadf85f6735c37b4dcb3aa5e81037bff7bd0a7cd639  $tmp/zh-TW_dev_0/common_voice_zh-TW_17396052.mp3
697871c82f66802537249ef323333eeebfd179eaa520bc682de58914a08a7b11  $tmp/zh-TW_dev_0/common_voice_zh-TW_19516543.mp3
2b7a600a24f0ce7125cbd3caa51a6418d5e0ab30118e35aa944812d20989189e  $tmp/zh-TW_dev_0/common_voice_zh-TW_20964151.mp3
6d88fd5444d18f588cddaf748f4cdbd217b72b7ab8e4f4635fe46d57db1534fd  $tmp/zh-TW_dev_0/common_voice_zh-TW_31113143.mp3
151c33b8b4785adb812f12a369d81ef96133c415e59fa9285e94ebfe3b9e9418  $tmp/zh-TW_dev_0/common_voice_zh-TW_25016944.mp3
53357f8856921983e1084924bc9f68fdcf9e6116b5651ac0d10efad39b3b04cf  $tmp/zh-TW_dev_0/common_voice_zh-TW_17380171.mp3
a0052ce9e62c8e406f3fca011888c76327f3af10953453a3c08086a044f775e0  $tmp/zh-TW_dev_0/common_voice_zh-TW_26931726.mp3
b0973be66461a0dc6df66dc0ad2f6bb93233a1c28428b5e75e432b3846882192  $tmp/zh-TW_dev_0/common_voice_zh-TW_19739280.mp3
460a20c1fb07f456deb12a64db0eb0127bfe6a50ecfab409a9f84b2ac88f8d40  $tmp/zh-TW_dev_0/common_voice_zh-TW_22053420.mp3
bd4f7a628d0ac5da4486849b31271cfcf101e375e8b98f9a5fb44f7144be9b62  $tmp/zh-TW_dev_0/common_voice_zh-TW_23377180.mp3
378fd8088783a64f18c0eca1d7045322fc440e15ec138ee75b34756304b53250  $tmp/zh-TW_dev_0/common_voice_zh-TW_26992639.mp3
b108e0db5e5f08a9a0e771e403d39aeb6fbca80788e4797e4bfae4264cec1152  $tmp/zh-TW_dev_0/common_voice_zh-TW_17383515.mp3
f8deffbd916ca0f4aa391e2c1a0e3f23f16b0385078bfd84ef283dec094dacca  $tmp/zh-TW_dev_0/common_voice_zh-TW_18669890.mp3
aa240ed585b3a6b28a10d90364c57bcf3cfaed6eea60b582c3594988ea7e9395  $tmp/zh-TW_dev_0/common_voice_zh-TW_19506878.mp3
e98273a48787adbb21d3d4aee61147f99656d9ecb524bd2299dc1683eed52723  $tmp/zh-TW_dev_0/common_voice_zh-TW_17413347.mp3
4c2d583aa29743ccb22cc37522637b93d03a265a95fef5f759d58d0e3c6f44d6  $tmp/zh-TW_dev_0/common_voice_zh-TW_32240866.mp3
965e65a8eba297e951212d051486558c0d24438edfd78ba820dbc0d99c2d9e80  $tmp/zh-TW_dev_0/common_voice_zh-TW_22426352.mp3
088185c759f62d5a22b1ccc855d05d4f654362d449bf8e09123742fdcc5a3cb0  $tmp/zh-TW_dev_0/common_voice_zh-TW_18744205.mp3
ed6c464ed2c7d0d7d6d7aafce32d5f906d0d1889d630cd7e592cf1b1360d682f  $tmp/zh-TW_dev_0/common_voice_zh-TW_32158843.mp3
CLIPSHA
}

fetch_cv_zhtw() {
  local need=0 gi
  for gi in 1 2 3 4; do [ -f "$DEST/cv-zhtw-$gi.wav" ] || need=1; done
  if [ "$need" = 1 ]; then
    preflight_concat_tools || return 1
    local tmp; tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"; trap - RETURN' RETURN  # self-clearing — a leaked RETURN trap re-fires on the NEXT function return with $tmp out of scope (set -u kill, #34)
    curl -fsSL --max-time 900 -o "$tmp/zh-TW_dev_0.tar" \
      "https://huggingface.co/datasets/fsicoli/common_voice_17_0/resolve/$CV_ZHTW_REV/audio/zh-TW/dev/zh-TW_dev_0.tar"
    echo "$CV_ZHTW_TAR_SHA  $tmp/zh-TW_dev_0.tar" | shasum -a 256 -c - >/dev/null \
      || { echo "✗ raw Common Voice zh-TW shard digest mismatch — refusing to parse" >&2; return 1; }
    local f picks converted
    for gi in 1 2 3 4; do
      for f in $(cv_zhtw_group_picks "$gi"); do
        tar -xf "$tmp/zh-TW_dev_0.tar" -C "$tmp" "zh-TW_dev_0/$f"
      done
    done
    verify_zhtw_clips "$tmp" \
      || { echo "✗ Common Voice zh-TW per-clip digest mismatch — refusing to parse" >&2; return 1; }
    for gi in 1 2 3 4; do
      picks=$(cv_zhtw_group_picks "$gi")
      converted=""
      for f in $picks; do
        # clips are MP3 — convert each BEFORE the python3 wave concat (#34 A2)
        afconvert -f WAVE -d LEI16@16000 -c 1 "$tmp/zh-TW_dev_0/$f" "$tmp/zh-TW_dev_0/${f%.mp3}.pcm16.wav"
        converted="$converted ${f%.mp3}.pcm16.wav"
      done
      concat_pcm16 "$tmp/zh-TW_dev_0" "$tmp/cv-zhtw-$gi.wav" $converted
      echo "$(cv_zhtw_group_sha "$gi")  $tmp/cv-zhtw-$gi.wav" | shasum -a 256 -c - >/dev/null \
        || { echo "✗ cv-zhtw-$gi converted-artifact digest mismatch — likely afconvert/CoreAudio drift; nothing registered for this group" >&2; return 1; }
      mv "$tmp/cv-zhtw-$gi.wav" "$DEST/cv-zhtw-$gi.wav"
    done
  fi
  for gi in 1 2 3 4; do
    echo "$(cv_zhtw_group_sha "$gi")  $DEST/cv-zhtw-$gi.wav" | shasum -a 256 -c - >/dev/null \
      || { echo "✗ cv-zhtw-$gi.wav digest mismatch — remove it to rebuild" >&2; return 1; }
  done
  cat > "$DEST/cv-zhtw_ATTRIBUTION.txt" <<'NOTICE'
Common Voice zh-TW corpora (cv-zhtw-1..4 .wav/.srt) are built from Mozilla
Common Voice (Corpus 17.0, zh-TW), CC-0 public-domain dedication —
https://commonvoice.mozilla.org — fetched from the fsicoli/common_voice_17_0
Hugging Face mirror at a pinned, digest-verified revision.
NOTICE
  write_cv_zhtw_srts
  for gi in 1 2 3 4; do
    "$BIN" corpus add "$DEST/cv-zhtw-$gi.wav" "$DEST/cv-zhtw-$gi.srt" --language zh --name "cv-zhtw-$gi"
  done
}

write_cv_zhtw_srts() {
  cat > "$DEST/cv-zhtw-1.srt" <<'SRT'
1
00:00:00,000 --> 00:00:05,256
比起電話，通訊軟體可達成短時間多工的回覆

2
00:00:05,256 --> 00:00:10,224
法律應保障所有的人獲得相同的發展結果

3
00:00:10,224 --> 00:00:13,500
七種資料結構

4
00:00:13,500 --> 00:00:17,280
超過名額就要抽籤了

5
00:00:17,280 --> 00:00:20,976
長期以來致力推動

6
00:00:20,976 --> 00:00:23,232
次元刀拔雜草
SRT
  cat > "$DEST/cv-zhtw-2.srt" <<'SRT'
1
00:00:00,000 --> 00:00:05,736
你給我聽好了，以後只有我才有資格讓你流淚

2
00:00:05,736 --> 00:00:12,000
吃葡萄不吐葡萄皮，倒吃葡萄倒吐葡萄皮

3
00:00:12,000 --> 00:00:15,960
五股泰山輕軌

4
00:00:15,960 --> 00:00:19,956
也許對你們工作有幫助

5
00:00:19,956 --> 00:00:22,980
七星主峰更勝東峰

6
00:00:22,980 --> 00:00:26,688
法國拿破崙三世
SRT
  cat > "$DEST/cv-zhtw-3.srt" <<'SRT'
1
00:00:00,000 --> 00:00:06,336
牛仔褲為美國最初為加州淘金工人所設計的

2
00:00:06,336 --> 00:00:11,664
唯有內心充滿光明，才能消滅一切的黑暗

3
00:00:11,664 --> 00:00:15,240
還是要花三十分鐘安裝

4
00:00:15,240 --> 00:00:19,848
只要鞏固了民族主義

5
00:00:19,848 --> 00:00:23,784
台北市是政經決策中樞

6
00:00:23,784 --> 00:00:27,024
苗栗幅員遼闊
SRT
  cat > "$DEST/cv-zhtw-4.srt" <<'SRT'
1
00:00:00,000 --> 00:00:06,336
一直愛你是我的驕傲，丟了你我怎麼炫耀

2
00:00:06,336 --> 00:00:10,200
也要陪你一起加班

3
00:00:10,200 --> 00:00:14,016
柴埕市民活動中心

4
00:00:14,016 --> 00:00:18,360
建立常態緊密的溝通機制

5
00:00:18,360 --> 00:00:21,504
否則予以廢止

6
00:00:21,504 --> 00:00:25,680
臺大五號館西側
SRT
}

FETCH_FAILURES=0

run_fetch() {  # $1 = label; rest = command — isolate每個語料：一個失敗不擋其他（partial success）
  local label="$1"; shift
  if ! "$@"; then
    echo "⚠ $label skipped (see error above) — continuing with the remaining corpora" >&2
    FETCH_FAILURES=$((FETCH_FAILURES + 1))
  fi
}

# en first (reliable, pre-existing); every corpus is isolated so partial
# success is real (#18 verify). The set is en + TRADITIONAL Chinese + ja —
# no Simplified Chinese (#34).
run_fetch "jfk (en)"            fetch_jfk
run_fetch "osr-harvard-1 (en)"  fetch_osr1
run_fetch "osr-harvard-2 (en)"  fetch_osr2
run_fetch "osr-harvard-3 (en)"  fetch_osr3
run_fetch "fleurs-ja groups (ja)" fetch_fleurs_ja
run_fetch "cv-zhtw groups (zh-TW)" fetch_cv_zhtw
echo "✓ Standard corpora registered (en + zh-TW + ja; failures above, if any, were skipped):"
"$BIN" corpus list
exit $((FETCH_FAILURES > 0 ? 1 : 0))
