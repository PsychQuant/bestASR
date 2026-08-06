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
INSTALL_DIR="$HOME/bin"
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

# Read currently installed version from sidecar (empty string if file missing/unreadable).
INSTALLED_VERSION=""
[[ -f "$VERSION_FILE" ]] && INSTALLED_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)

# Decide whether to RESOLVE (a cheap metadata call). Whether to actually
# download is decided after resolution, against the tag we really got — see
# below.
NEED_DOWNLOAD=false
REASON=""
if [[ ! -x "$BINARY" ]]; then
    NEED_DOWNLOAD=true
    REASON="binary not installed"
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
    ACTUAL_VERSION=""
    for API_URL in \
        "${DESIRED_VERSION:+https://api.github.com/repos/$REPO/releases/tags/v$DESIRED_VERSION}" \
        "https://api.github.com/repos/$REPO/releases/latest"
    do
        [[ -z "$API_URL" ]] && continue
        RESPONSE=$(curl -sL --max-time 30 "$API_URL" 2>/dev/null) || continue
        URL=$(printf '%s' "$RESPONSE" \
            | grep '"browser_download_url"' | grep "/$BINARY_NAME\"" | head -1 \
            | sed 's/.*"\(https[^"]*\)".*/\1/')
        if [[ -n "$URL" ]]; then
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
        if curl -sL --max-time 300 "$URL" -o "${BINARY}.tmp" 2>/dev/null; then
            chmod +x "${BINARY}.tmp"
            # Strip the download quarantine so Gatekeeper's online notarization
            # check runs clean on the notarized binary (bare executables can't be
            # stapled; the ticket lives on Apple's servers).
            xattr -d com.apple.quarantine "${BINARY}.tmp" 2>/dev/null || true
            mv "${BINARY}.tmp" "$BINARY"
            # Record what we RECEIVED, never what we asked for (#163).
            echo "${ACTUAL_VERSION:-unknown}" > "$VERSION_FILE"
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
