#!/bin/bash
# Version-aware auto-download wrapper for bestasr-mcp.
#
# Mirrors the che-mcps family pattern (e.g. che-apple-notes-mcp): the plugin
# ships this small script; the real binary is a signed + notarized asset on
# GitHub Releases, fetched on first spawn.
#
# Design:
# - Reads desired version from plugin.json (plugin's intended binary version)
# - Compares against ~/bin/.bestasr-mcp.version sidecar
# - Re-downloads when the plugin has been updated but the binary is stale
# - Atomic file swap (.tmp + mv) so partial downloads never break things
# - Falls back to releases/latest if plugin.json unreadable or pinned tag missing
#
# Note for contributors: if you built bestasr-mcp from source via
# scripts/install.sh, this wrapper will replace ~/bin/bestasr-mcp with the
# released (notarized) build on version mismatch. Re-run scripts/install.sh
# afterward to go back to your local build.

set -u

REPO="PsychQuant/bestASR"
BINARY_NAME="bestasr-mcp"
# Overridable so the sidecar/self-heal logic is testable without touching the
# real ~/bin (#163 verify: "defect 3's fix ships with no test"). Production
# behaviour is unchanged — the variable is unset outside tests.
INSTALL_DIR="${BESTASR_WRAPPER_INSTALL_DIR:-$HOME/bin}"
BINARY="$INSTALL_DIR/$BINARY_NAME"
VERSION_FILE="$INSTALL_DIR/.${BINARY_NAME}.version"

# Locate plugin root via wrapper's own path (more reliable than $CLAUDE_PLUGIN_ROOT
# which isn't guaranteed in the MCP spawn env). Wrapper lives at PLUGIN_ROOT/bin/*.sh.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

# Read desired version from plugin.json (empty string on any failure → fallback to "latest").
DESIRED_VERSION=""
if [[ -f "$PLUGIN_JSON" ]]; then
    DESIRED_VERSION=$(grep -oE '"version":[[:space:]]*"[^"]+"' "$PLUGIN_JSON" 2>/dev/null \
        | head -1 | cut -d'"' -f4 || true)
fi

# Read the installed version from the sidecar.
#
# The sidecar is schema-tagged `v2:<tag>` (#163 verify B1). An *untagged* value
# was written by a pre-fix wrapper that recorded the version it ASKED FOR rather
# than the one it received — the exact lie this issue is about. Machines in that
# state have sidecar 0.16.0, plugin.json 0.16.0, and a crashing 0.15.0 binary;
# with the old equality check they short-circuited before any resolution and
# would have kept the broken binary forever, even after a fixed release.
#
# So: a legacy sidecar is treated as UNKNOWN, which forces exactly one
# resolution. That is what actually heals the installed base — fixing only the
# write path heals nobody who is already poisoned.
INSTALLED_VERSION=""
LEGACY_SIDECAR=false
SIDECAR_RAW=""
[[ -f "$VERSION_FILE" ]] && SIDECAR_RAW=$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)
case "$SIDECAR_RAW" in
    v2:*) INSTALLED_VERSION="${SIDECAR_RAW#v2:}" ;;
    "")   : ;;                                  # no sidecar — first install
    *)    LEGACY_SIDECAR=true ;;                # untrusted, force one resolve
esac

# Decide whether to RESOLVE (a cheap metadata call). Whether to actually
# download is decided after resolution, against the tag we really got — see
# below.
NEED_DOWNLOAD=false
REASON=""
if [[ ! -x "$BINARY" ]]; then
    NEED_DOWNLOAD=true
    REASON="binary not installed"
elif $LEGACY_SIDECAR; then
    NEED_DOWNLOAD=true
    REASON="sidecar predates the #163 fix and cannot be trusted — re-resolving once"
elif [[ -n "$DESIRED_VERSION" ]] && [[ "$INSTALLED_VERSION" != "$DESIRED_VERSION" ]]; then
    NEED_DOWNLOAD=true
    REASON="plugin wants v${DESIRED_VERSION}, installed is v${INSTALLED_VERSION:-unknown}"
fi

if $NEED_DOWNLOAD; then
    echo "$BINARY_NAME: $REASON — checking $REPO..." >&2
    mkdir -p "$INSTALL_DIR"

    # Try pinned tag first, then fall back to latest release. Capture the tag we
    # ACTUALLY resolved alongside the URL: when the pinned tag does not exist we
    # silently land on `releases/latest`, and recording the requested version
    # instead of the received one is what made this wrapper unable to ever
    # self-heal (#163) — the sidecar claimed the desired version, the next run
    # compared equal, and the stale binary stayed forever.
    URL=""
    SHA_URL=""
    ACTUAL_VERSION=""
    for API_URL in \
        "${DESIRED_VERSION:+https://api.github.com/repos/$REPO/releases/tags/v$DESIRED_VERSION}" \
        "https://api.github.com/repos/$REPO/releases/latest"
    do
        [[ -z "$API_URL" ]] && continue
        RESPONSE=$(curl -fsSL --max-time 30 "$API_URL" 2>/dev/null) || continue
        URL=$(printf '%s' "$RESPONSE" \
            | grep '"browser_download_url"' | grep "/$BINARY_NAME\"" | head -1 \
            | sed 's/.*"\(https[^"]*\)".*/\1/')
        if [[ -n "$URL" ]]; then
            # The release always publishes a companion checksum
            # (scripts/release-mcp.sh) — it existed all along with no consumer.
            SHA_URL=$(printf '%s' "$RESPONSE" \
                | grep '"browser_download_url"' | grep "/$BINARY_NAME.sha256\"" | head -1 \
                | sed 's/.*"\(https[^"]*\)".*/\1/')
            ACTUAL_VERSION=$(printf '%s' "$RESPONSE" \
                | grep -m1 '"tag_name"' \
                | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
                | sed 's/^v//')
            break
        fi
    done

    # Already running the exact build the registry would hand us: correct the
    # sidecar and skip the transfer. Without this the unsatisfiable-pin case
    # (plugin.json ahead of the newest release) re-downloads on every launch.
    if [[ -n "$URL" && -x "$BINARY" && -n "$ACTUAL_VERSION" \
          && "$ACTUAL_VERSION" == "$INSTALLED_VERSION" ]]; then
        echo "$BINARY_NAME: v${ACTUAL_VERSION} is the newest published release" \
             "(plugin pins v${DESIRED_VERSION:-?}, not published yet) — keeping it" >&2
        URL=""
        NEED_DOWNLOAD=false
    fi
fi

if $NEED_DOWNLOAD; then

    if [[ -z "$URL" ]]; then
        if [[ -x "$BINARY" ]]; then
            echo "$BINARY_NAME: WARNING — no download URL found, keeping existing binary" >&2
        else
            echo "$BINARY_NAME: ERROR — no download URL found at $REPO." >&2
            echo "$BINARY_NAME: build from source instead: git clone https://github.com/$REPO && cd bestASR && bash scripts/install.sh" >&2
            exit 1
        fi
    else
        if curl -fsSL --max-time 300 "$URL" -o "${BINARY}.tmp" 2>/dev/null; then
            # Verify BEFORE trusting it (#163 verify B3). This path used to
            # download an executable, strip its quarantine, and exec it with no
            # integrity check at all — while the release had been publishing a
            # .sha256 with no consumer the whole time. Stripping quarantine is
            # not "letting Gatekeeper run cleanly", it *skips* the evaluation,
            # so this is the only check standing between a tampered release
            # asset and execution. Refuse rather than warn.
            VERIFIED=false
            if [[ -n "$SHA_URL" ]] \
                && EXPECTED=$(curl -fsSL --max-time 30 "$SHA_URL" 2>/dev/null | awk '{print $1}') \
                && [[ -n "$EXPECTED" ]]; then
                ACTUAL_SHA=$(shasum -a 256 "${BINARY}.tmp" | awk '{print $1}')
                if [[ "$EXPECTED" == "$ACTUAL_SHA" ]]; then
                    VERIFIED=true
                else
                    echo "$BINARY_NAME: ERROR — checksum mismatch (expected ${EXPECTED:0:12}…, got ${ACTUAL_SHA:0:12}…); refusing to install" >&2
                fi
            else
                echo "$BINARY_NAME: ERROR — no usable .sha256 for this release; refusing to install an unverified binary" >&2
            fi

            # Developer ID signature must also validate. Notarization is stapled
            # to Apple's servers for bare executables, so this is a local
            # structural check, not a notarization check — but a tampered binary
            # fails it, and it costs nothing.
            if $VERIFIED && ! codesign --verify --strict "${BINARY}.tmp" 2>/dev/null; then
                echo "$BINARY_NAME: ERROR — code signature invalid; refusing to install" >&2
                VERIFIED=false
            fi

            if ! $VERIFIED; then
                rm -f "${BINARY}.tmp" 2>/dev/null
                if [[ -x "$BINARY" ]]; then
                    echo "$BINARY_NAME: keeping the existing binary" >&2
                    exec "$BINARY" "$@"
                fi
                exit 1
            fi

            chmod +x "${BINARY}.tmp"
            # Quarantine is stripped only after the checks above have passed.
            xattr -d com.apple.quarantine "${BINARY}.tmp" 2>/dev/null || true
            mv "${BINARY}.tmp" "$BINARY"
            # Record what we RECEIVED, never what we asked for, schema-tagged so
            # a future wrapper can tell this value apart from a pre-fix one.
            echo "v2:${ACTUAL_VERSION:-unknown}" > "$VERSION_FILE"
            if [[ -n "$DESIRED_VERSION" && -n "$ACTUAL_VERSION" \
                  && "$ACTUAL_VERSION" != "$DESIRED_VERSION" ]]; then
                echo "$BINARY_NAME: installed v${ACTUAL_VERSION} — note: plugin pins" \
                     "v${DESIRED_VERSION}, which has no published release" >&2
            else
                echo "$BINARY_NAME: installed v${ACTUAL_VERSION:-unknown}" >&2
            fi
        else
            rm -f "${BINARY}.tmp" 2>/dev/null
            if [[ -x "$BINARY" ]]; then
                echo "$BINARY_NAME: WARNING — download failed, keeping existing binary" >&2
            else
                echo "$BINARY_NAME: ERROR — download failed" >&2
                exit 1
            fi
        fi
    fi
fi

exec "$BINARY" "$@"
