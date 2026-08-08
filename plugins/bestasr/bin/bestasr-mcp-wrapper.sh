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

# What we accept, and it has to be all four things at once: our program, our
# team, a real Apple chain, and a Developer ID Application certificate.
#
# This string is not hand-rolled. It is the requirement Apple's own tooling
# generates for our release binary — read it back with:
#
#   codesign -d -r- ~/bin/bestasr-mcp
#
# Round 2 replaced a bare `codesign --verify --strict` (which pins nothing at
# all) with a hand-written requirement that kept only two of Apple's five
# clauses, and round 3 broke it twice, empirically, on this machine:
#
#   * No `identifier` clause meant it pinned WHO signed, not WHAT was signed.
#     Any other binary from the same team passed: `cp ~/bin/CheWordMCP
#     ./bestasr-mcp` was accepted, and every one of our MCP binaries is a
#     public release asset. No forgery required.
#   * No certificate-type clause meant an "Apple Development" certificate
#     passed, because it carries the same `subject.OU`. That identity is
#     auto-issued by Xcode and signs with no password prompt — so local
#     execution on any of our machines was enough, without ever touching the
#     release key, CI, or GitHub.
#
# Hence: stop inventing requirements, use the one Apple generates. The two
# OID clauses are what constrain the certificate to Developer ID Application
# (leaf 1.2.840.113635.100.6.1.13) issued under the Developer ID CA
# (intermediate 1.2.840.113635.100.6.2.6).
EXPECTED_TEAM_ID="6W377FS7BS"
EXPECTED_IDENTIFIER="bestasr-mcp"
SIGNING_REQUIREMENT='=identifier "'"$EXPECTED_IDENTIFIER"'"'
SIGNING_REQUIREMENT="$SIGNING_REQUIREMENT"' and anchor apple generic'
SIGNING_REQUIREMENT="$SIGNING_REQUIREMENT"' and certificate 1[field.1.2.840.113635.100.6.2.6]'
SIGNING_REQUIREMENT="$SIGNING_REQUIREMENT"' and certificate leaf[field.1.2.840.113635.100.6.1.13]'
SIGNING_REQUIREMENT="$SIGNING_REQUIREMENT"' and certificate leaf[subject.OU] = "'"$EXPECTED_TEAM_ID"'"'

# Verification is a function, not an inline call, because round 3 found the
# inline version only guarded the download path — every route to an existing
# binary reached `exec` unchecked.
verify_binary() {
    codesign --verify --strict -R "$SIGNING_REQUIREMENT" "$1" 2>/dev/null
}
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
# So: a legacy sidecar is treated as UNKNOWN, which forces the machine back
# through resolution rather than short-circuiting. That is what heals the
# installed base — fixing only the write path heals nobody already poisoned.
# It guarantees re-resolution, not success in one attempt: if the registry
# offers no matching asset, or verification fails on a clean install, the
# sidecar is left untouched and the next spawn tries again.
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
        # Extract each asset URL as its own token before selecting.
        #
        # The previous form ran a greedy `sed 's/.*"\(https[^"]*\)".*/\1/'` over
        # whatever line matched. Real GitHub responses are pretty-printed so one
        # asset sits per line and it happened to work — but on a single-line
        # response the greedy `.*` skips to the LAST url on the line, selecting
        # the .sha256 as if it were the binary. Round-1 M4 flagged the fragility;
        # a stubbed single-line registry in the tests then reproduced it exactly.
        # `grep -o` + an anchored match removes the positional guesswork, and
        # anchoring also escapes the `.` that round-2 M6 caught unescaped.
        ASSET_URLS=$(printf '%s' "$RESPONSE" \
            | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' \
            | grep -o 'https[^"]*')
        URL=$(printf '%s\n' "$ASSET_URLS" | grep -E "/${BINARY_NAME}$" | head -1)
        if [[ -n "$URL" ]]; then
            # The release always publishes a companion checksum
            # (scripts/release-mcp.sh) — it existed all along with no consumer.
            SHA_URL=$(printf '%s\n' "$ASSET_URLS" \
                | grep -E "/${BINARY_NAME}\.sha256$" | head -1)
            ACTUAL_VERSION=$(printf '%s' "$RESPONSE" \
                | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
                | grep -o '"[^"]*"$' | tr -d '"' | sed 's/^v//')
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
            # PRIMARY control: pin the signing IDENTITY, not merely "is signed".
            #
            # The first attempt used `codesign --verify --strict` alone and a
            # checksum, and round-2 review showed that combination is close to
            # no defence at all against the threat it named:
            #
            #   * `--verify --strict` only checks the signature is internally
            #     self-consistent, never WHO signed. Verified locally: an
            #     unsigned binary passes (Apple Silicon's linker applies an
            #     ad-hoc signature automatically), and `codesign --sign -` —
            #     free, anonymous, no developer account — also passes, with
            #     TeamIdentifier=not set.
            #   * the checksum came from the SAME release-API response as the
            #     binary, so whoever can replace one asset replaces both.
            #
            # The designated requirement below fixes the first: `anchor apple
            # generic` forces the chain to Apple's root, and the leaf OU pins
            # our Team. Verified against a real release (passes), an ad-hoc
            # binary (rejected), and a self-signed one (rejected).
            VERIFIED=false
            if verify_binary "${BINARY}.tmp"; then
                VERIFIED=true
            else
                echo "$BINARY_NAME: ERROR — binary is not signed by the expected identity (Team $EXPECTED_TEAM_ID); refusing to install" >&2
            fi

            # SECONDARY, advisory: the checksum. It shares a channel with the
            # artifact it validates, so it cannot attest provenance — it catches
            # transit corruption, which is worth catching. A mismatch is fatal
            # (something is genuinely wrong); a MISSING .sha256 is not, because
            # letting a maintainer's forgotten upload brick every clean install
            # trades one outage for another (round-2 H3).
            if $VERIFIED && [[ -n "$SHA_URL" ]]; then
                if EXPECTED=$(curl -fsSL --max-time 30 "$SHA_URL" 2>/dev/null | awk '{print $1}') \
                    && [[ -n "$EXPECTED" ]]; then
                    ACTUAL_SHA=$(shasum -a 256 "${BINARY}.tmp" | awk '{print $1}')
                    if [[ "$EXPECTED" != "$ACTUAL_SHA" ]]; then
                        echo "$BINARY_NAME: ERROR — checksum mismatch (expected ${EXPECTED:0:12}…, got ${ACTUAL_SHA:0:12}…); refusing to install" >&2
                        VERIFIED=false
                    fi
                else
                    echo "$BINARY_NAME: note — .sha256 listed but unreadable; relying on the signing-identity check" >&2
                fi
            fi

            if ! $VERIFIED; then
                rm -f "${BINARY}.tmp" 2>/dev/null
                if [[ -x "$BINARY" ]]; then
                    # Fall through to the single gated exec below rather than
                    # exec'ing here: an existing binary is not trusted just
                    # because it predates this run (#163 round-3 H1).
                    echo "$BINARY_NAME: keeping the existing binary" >&2
                else
                    exit 1
                fi
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

# The only exec in this script, and it is gated. Round 2 verified the binary at
# download time only, so the fast path (sidecar already matches) and all three
# keep-existing branches ran whatever was on disk without a check — including,
# after a failed re-download, the very binary the user was trying to replace.
# Verifying here costs one codesign call per spawn and covers every route.
if [[ ! -x "$BINARY" ]]; then
    echo "$BINARY_NAME: ERROR — no binary at $BINARY" >&2
    exit 1
fi
if ! verify_binary "$BINARY"; then
    echo "$BINARY_NAME: ERROR — $BINARY does not satisfy the pinned signing requirement" >&2
    echo "  (expected identifier '$EXPECTED_IDENTIFIER', Developer ID Application, Team $EXPECTED_TEAM_ID)" >&2
    echo "  Refusing to run it. Delete it and re-run to reinstall from the release." >&2
    exit 1
fi
exec "$BINARY" "$@"
