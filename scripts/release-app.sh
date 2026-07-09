#!/bin/bash
# Build, assemble, sign, notarize, STAPLE, and zip the dual-track bestASR.app
# bundle (#87, spec gui-app): GUI (bestASR) + MCP helper (bestasr-mcp) + CLI
# (bestasr) in one Developer ID bundle. Stapling is the bundle-only capability
# that motivated this surface — offline Gatekeeper verification.
#
#   scripts/release-app.sh                  # full pipeline (maintainer machine)
#   scripts/release-app.sh --assemble-only  # unsigned bundle, no credentials
#
# Env overrides:
#   DEVELOPER_ID / NOTARY_PROFILE  signing handles (reference names, not secrets)
#   BIN_DIR   directory holding prebuilt bestASR/bestasr-mcp/bestasr — skips the
#             build stage (used by the bundle smoke test with stub binaries)
#   OUT_DIR   where bestASR.app (and the final zip) land; default dist/
set -euo pipefail

ASSEMBLE_ONLY=0
[ "${1:-}" = "--assemble-only" ] && ASSEMBLE_ONLY=1

DEVELOPER_ID="${DEVELOPER_ID:-F2523DCF6D02BE99B67C7D27F633119292DA4934}"
NOTARY_PROFILE="${NOTARY_PROFILE:-che-mcps-notary}"
BUNDLE_ID="com.psychquant.bestASR"
MIN_OS="14.0"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Single source of truth for the version: BestASRVersion.current (the bundle
# smoke test asserts the plist matches this constant — no drift).
VERSION="$(sed -n 's/.*static let current = "\([0-9][0-9.]*\)".*/\1/p' \
  Sources/BestASRKit/Models/DataModels.swift | head -1)"
[ -n "$VERSION" ] || { echo "x could not parse BestASRVersion.current" >&2; exit 1; }

OUT_DIR="${OUT_DIR:-dist}"
APP="$OUT_DIR/bestASR.app"
MACOS_DIR="$APP/Contents/MacOS"

if [ -z "${BIN_DIR:-}" ]; then
  echo "== [1/7] build release binaries (universal) =="
  command -v swift >/dev/null 2>&1 || { echo "x swift not found" >&2; exit 1; }
  # Same swiftly-6.2.4 release-crash workaround as release-mcp.sh.
  BUILD_ENV=()
  if [[ "$(command -v swift)" == *".swiftly"* ]] && swift --version 2>&1 | grep -q "6.2.4"; then
    echo "! swiftly swift-6.2.4 detected — building with the Xcode toolchain (/usr/bin/swift)."
    BUILD_ENV=(env PATH="/usr/bin:$PATH")
  fi
  # One invocation per product: swift build accepts a single --product
  # (repeats silently keep only the last one — caught by the real-build check).
  for product in bestasr-gui bestasr-mcp bestasr; do
    "${BUILD_ENV[@]}" swift build -c release --arch arm64 --arch x86_64 --product "$product"
  done
  BIN_DIR=".build/apple/Products/Release"
else
  echo "== [1/7] using prebuilt binaries from BIN_DIR=$BIN_DIR =="
fi

for bin in bestasr-gui bestasr-mcp bestasr; do
  [ -x "$BIN_DIR/$bin" ] || { echo "x missing executable: $BIN_DIR/$bin" >&2; exit 1; }
done

echo "== [2/7] assemble $APP (v$VERSION) =="
rm -rf "$APP"
mkdir -p "$MACOS_DIR"
# The GUI executable takes the bundle's display name (CFBundleExecutable).
# The CLI copy is bestasr-cli: default APFS is case-insensitive, so a file
# named "bestasr" IS "bestASR" — copying it would overwrite the GUI (spec
# gui-app; caught by BundleAssemblyTests).
cp "$BIN_DIR/bestasr-gui" "$MACOS_DIR/bestASR"
cp "$BIN_DIR/bestasr-mcp" "$MACOS_DIR/bestasr-mcp"
cp "$BIN_DIR/bestasr" "$MACOS_DIR/bestasr-cli"
chmod +x "$MACOS_DIR"/*

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>bestASR</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>bestASR</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>$MIN_OS</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>NSHumanReadableCopyright</key>
	<string>© PsychQuant</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
echo "  ✓ bundle assembled"

if [ "$ASSEMBLE_ONLY" = 1 ]; then
  echo "✓ assemble-only: unsigned bundle at $APP (no signing credentials touched)"
  exit 0
fi

echo "== [3/7] codesign (nested executables first, then the bundle) =="
SIGN_ARGS=(--force --options runtime --timestamp --sign "$DEVELOPER_ID")
[ -n "${ENTITLEMENTS:-}" ] && SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
# Helpers are standalone Mach-Os inside the bundle; sign them before the app
# seal so the bundle signature covers their final bits.
codesign "${SIGN_ARGS[@]}" "$MACOS_DIR/bestasr-mcp"
codesign "${SIGN_ARGS[@]}" "$MACOS_DIR/bestasr-cli"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"
echo "  ✓ signed"

echo "== [4/7] smoke-test the SIGNED helper under hardened runtime =="
# The GUI can't be exercised headless, but the bundled MCP helper can: a real
# stdio round-trip proves hardened runtime didn't break the embedded binaries.
SMOKE_IN="$(mktemp)"; trap 'rm -f "$SMOKE_IN"' EXIT
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"release-smoke","version":"0"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
} > "$SMOKE_IN"
SMOKE_OUT="$({ cat "$SMOKE_IN"; sleep 3; } | "$MACOS_DIR/bestasr-mcp" 2>/dev/null || true)"
echo "$SMOKE_OUT" | grep -q '"transcribe"' || {
  echo "x smoke test FAILED — signed bundled bestasr-mcp did not answer tools/list" >&2
  exit 1
}
echo "  ✓ bundled helper answers tools/list"

echo "== [5/7] notarize (submit + wait) =="
NOTARIZE_ZIP="$(mktemp -d)/bestASR.app.zip"
ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "== [6/7] staple + validate (the bundle-only offline-verification win) =="
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
echo "  ✓ stapled"

echo "== [7/7] final artifact =="
FINAL_ZIP="$OUT_DIR/bestASR-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"
( cd "$OUT_DIR" && shasum -a 256 "bestASR-$VERSION.zip" | tee "bestASR-$VERSION.zip.sha256" )

echo ""
echo "✓ stapled bundle: $APP"
echo "✓ artifact:       $FINAL_ZIP"
echo "  publish:        gh release upload v$VERSION $FINAL_ZIP $FINAL_ZIP.sha256 --repo PsychQuant/bestASR"
echo "  agents:         claude mcp add bestasr -- /Applications/bestASR.app/Contents/MacOS/bestasr-mcp"
