#!/bin/bash
# Build, sign, notarize, and publish the bestasr-mcp binary to a GitHub Release
# so the plugin's bin/bestasr-mcp-wrapper.sh can auto-download it (che-mcps
# family pattern).
#
#   scripts/release-mcp.sh 0.11.0
#
# Requires (all already provisioned on the maintainer's machine — see the
# "Apple Developer / Notarization Pipeline" section of the global CLAUDE.md):
#   - a "Developer ID Application" codesigning identity      → $DEVELOPER_ID
#   - a stored notarytool keychain profile                   → $NOTARY_PROFILE
#   - gh authenticated with write access to $REPO
#
# DEVELOPER_ID / NOTARY_PROFILE are reference handles (a cert SHA-1 and a
# keychain profile name), not secrets — safe to default here, overridable by env.
set -euo pipefail

VERSION="${1:?usage: scripts/release-mcp.sh <version>  (e.g. 0.11.0)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "x version must be semver X.Y.Z, got: $VERSION" >&2; exit 1; }
TAG="v$VERSION"

REPO="PsychQuant/bestASR"
DEVELOPER_ID="${DEVELOPER_ID:-F2523DCF6D02BE99B67C7D27F633119292DA4934}"
NOTARY_PROFILE="${NOTARY_PROFILE:-che-mcps-notary}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

command -v swift >/dev/null 2>&1 || { echo "x swift not found (install Xcode)" >&2; exit 1; }
command -v gh    >/dev/null 2>&1 || { echo "x gh not found" >&2; exit 1; }

# The swiftly-managed swift-6.2.4 toolchain reproducibly crashes -c release
# (same reason install.sh does the /usr/bin dance). Prefer the Xcode toolchain.
BUILD_ENV=()
if [[ "$(command -v swift)" == *".swiftly"* ]] && swift --version 2>&1 | grep -q "6.2.4"; then
  echo "! swiftly swift-6.2.4 detected — building with the Xcode toolchain (/usr/bin/swift)."
  BUILD_ENV=(env PATH="/usr/bin:$PATH")
fi

echo "== [1/6] build release bestasr-mcp =="
"${BUILD_ENV[@]}" swift build -c release --product bestasr-mcp
# SwiftPM maintains .build/release as a symlink to the active release bin dir.
BIN=".build/release/bestasr-mcp"
[ -x "$BIN" ] || { echo "x built binary not found at $BIN" >&2; exit 1; }

echo "== [2/6] codesign (Developer ID, hardened runtime, timestamp) =="
# Optional entitlements: pass ENTITLEMENTS=path to add hardened-runtime
# exceptions if a future ML dependency needs them (none required today).
SIGN_ARGS=(--force --options runtime --timestamp --sign "$DEVELOPER_ID")
[ -n "${ENTITLEMENTS:-}" ] && SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
codesign "${SIGN_ARGS[@]}" "$BIN"
codesign --verify --strict --verbose=2 "$BIN"

echo "== [3/6] smoke-test the SIGNED binary under hardened runtime =="
# A binary that crashes under hardened runtime must never reach a release.
# Drive a real stdio JSON-RPC round-trip: initialize + tools/list.
SMOKE_IN="$(mktemp)"; trap 'rm -f "$SMOKE_IN"' EXIT
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"release-smoke","version":"0"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
} > "$SMOKE_IN"
# Hold stdin open briefly after the messages: a real MCP client keeps the pipe
# open for the session, and closing it immediately races the server's
# EOF-triggered shutdown against the response flush (empty output, not a crash).
SMOKE_OUT="$({ cat "$SMOKE_IN"; sleep 3; } | "$BIN" 2>/dev/null || true)"
echo "$SMOKE_OUT" | grep -q '"transcribe"' || {
  echo "x smoke test FAILED — signed binary did not return the tool list." >&2
  echo "  (if this is a hardened-runtime crash, retry with ENTITLEMENTS=path/to/entitlements.plist)" >&2
  exit 1
}
echo "  ✓ signed binary answers tools/list"

echo "== [4/6] notarize (submit + wait) =="
ZIP="$(mktemp -d)/bestasr-mcp.zip"
ditto -c -k --keepParent "$BIN" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
# Bare executables can't be stapled; Gatekeeper verifies the ticket online.

echo "== [5/6] checksum =="
STAGE="$(mktemp -d)"
cp "$BIN" "$STAGE/bestasr-mcp"
( cd "$STAGE" && shasum -a 256 bestasr-mcp | tee bestasr-mcp.sha256 )

echo "== [6/6] publish GitHub release $TAG =="
SHA="$(git rev-parse --short HEAD)"
NOTES="bestasr-mcp $TAG — signed + notarized MCP server binary (arm64, Apple Silicon).

Auto-downloaded by the bestasr plugin's bin/bestasr-mcp-wrapper.sh.
Built from ${SHA}. Manual install: drop into a directory on PATH, or
\`claude mcp add bestasr -- /path/to/bestasr-mcp\`."
gh release create "$TAG" "$STAGE/bestasr-mcp" "$STAGE/bestasr-mcp.sha256" \
  --repo "$REPO" --title "$TAG" --notes "$NOTES"

echo ""
echo "✓ released $TAG with notarized bestasr-mcp"
echo "  next: bump plugins/bestasr/.claude-plugin/plugin.json to $VERSION, then /plugin-update bestasr"
