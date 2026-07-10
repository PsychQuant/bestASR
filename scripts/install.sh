#!/bin/bash
# One-command install: build the release binary with a known-good toolchain
# and put it on PATH.
#
#   bash scripts/install.sh              # installs to ~/bin (created if needed)
#   PREFIX=/usr/local/bin bash scripts/install.sh
#
# Why the toolchain dance: the swiftly-managed swift-6.2.4-RELEASE toolchain
# reproducibly crashes the compiler on `swift build -c release` (signal 6,
# SIL specialization in the swift-transformers dependency — see README
# Requirements). The Xcode built-in toolchain passes, so when swiftly is
# detected we build with /usr/bin first on PATH.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

command -v swift >/dev/null 2>&1 || {
  echo "x swift not found — install Xcode or the Command Line Tools first:" >&2
  echo "    xcode-select --install" >&2
  exit 1
}
ARCH="$(uname -m)"
[ "$ARCH" = "arm64" ] || {
  echo "x bestASR requires Apple Silicon (arm64); this machine is $ARCH" >&2
  exit 1
}

BUILD_ENV=()
if command -v swift >/dev/null && [[ "$(command -v swift)" == *".swiftly"* ]]; then
  SWIFT_VER="$(swift --version 2>&1 | head -1)"
  if [[ "$SWIFT_VER" == *"6.2.4"* ]]; then
    echo "! swiftly swift-6.2.4 detected — its release builds crash the compiler."
    echo "  Building with the Xcode built-in toolchain instead (/usr/bin/swift)."
    BUILD_ENV=(env PATH="/usr/bin:$PATH")
  fi
fi

echo "== building release binary (first build takes a few minutes) =="
# Bare build compiles every product — since #87 that includes the bestasr-gui
# SwiftUI app (a ride-along; only bestasr/bestasr-mcp are installed below).
# ${arr[@]+...}: /bin/bash 3.2 aborts on expanding an EMPTY array under set -u
# (verify #87 HIGH), which would kill exactly the non-swiftly default path.
${BUILD_ENV[@]+"${BUILD_ENV[@]}"} swift build -c release

PREFIX="${PREFIX:-$HOME/bin}"
mkdir -p "$PREFIX"
[ -w "$PREFIX" ] || {
  echo "x $PREFIX is not writable — re-run with a writable PREFIX, e.g.:" >&2
  echo "    PREFIX=\$HOME/bin bash scripts/install.sh" >&2
  exit 1
}
cp .build/release/bestasr "$PREFIX/bestasr"
cp .build/release/bestasr-mcp "$PREFIX/bestasr-mcp"

echo "== verifying =="
"$PREFIX/bestasr" list-backends

echo ""
echo "✓ installed: $PREFIX/bestasr"
case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *)
    echo "! $PREFIX is not on your PATH — add it to your shell profile:"
    echo "    export PATH=\"$PREFIX:\$PATH\""
    ;;
esac
echo ""
echo "Try it:"
echo "    bestasr diagnose                # what would this machine run?"
echo "    bestasr transcribe input.mp3    # first run downloads a model (~1.5 GB)"
