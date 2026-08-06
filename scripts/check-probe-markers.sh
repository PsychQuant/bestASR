#!/usr/bin/env bash
#
# check-probe-markers.sh — confirm hand-added probe markers reached a built binary.
#
# When you instrument a dependency checkout (see benchmarks/evidence/*.json,
# path_coverage.how), the dangerous failure is silent: a build that never picked
# up your patch produces a probe-free binary whose output is identical to the
# clean one, which reads as success. This checks the literals are in the artifact
# before you believe any count.
#
#   ./scripts/check-probe-markers.sh <binary> <marker>...
#
# Exit status
#   0  every marker found
#   1  a marker is missing
#   2  the marker list or the binary is unusable (nothing was checked)
#
# It is deliberately louder about status 2 than 1: "I could not check" and
# "I checked and it failed" are different answers, and earlier versions of this
# check reported the first as success.
#
# What it does NOT establish: that every probe *site* is present (only that the
# literals are), that any probe ran, or that the marker is in the architecture
# slice you will execute. See method_limits in the evidence file.

set -euo pipefail

# Byte semantics for the ASCII test below, and deterministic collation for grep
# and strings regardless of the caller's locale.
export LC_ALL=C

readonly EX_MISSING=1
readonly EX_UNUSABLE=2

die() { printf '%s: %s\n' "${0##*/}" "$1" >&2; exit "${2:-$EX_UNUSABLE}"; }

usage() {
    sed -n '3,26p' "$0" | sed 's|^# \{0,1\}||'
    exit "$EX_UNUSABLE"
}

[ "$#" -ge 2 ] || usage
case "$1" in -h|--help) usage ;; esac

exe=$1
shift
markers=("$@")

# --- the binary ---------------------------------------------------------------
# `--` and the ./ prefix keep a path that begins with `-` from being read as an
# option by strings.
case "$exe" in -*) exe="./$exe" ;; esac
[ -f "$exe" ] || die "not a file: $exe"
[ -r "$exe" ] || die "not readable: $exe"

# --- the marker contract ------------------------------------------------------
# Each rule below exists because violating it produces a WRONG answer rather than
# an error, which is worse.
[ "${#markers[@]}" -gt 0 ] || die "no markers given — nothing would be checked"

for m in "${markers[@]}"; do
    # An empty marker is a substring of everything: grep -F '' matches any input.
    [ -n "$m" ] || die "empty marker — it would match anything"

    # strings(1) emits printable runs of 4 or more characters by default, so a
    # shorter marker in an isolated run is reported missing when it is present.
    [ "${#m}" -ge 4 ] || die "marker shorter than 4 characters: '$m' — strings would not emit it"

    # strings splits a run at any byte >= 0x80, so a marker containing one
    # non-ASCII character can never be found, at any -n value. This binary
    # contains arrows and em-dashes; its strings output contains no non-ASCII
    # bytes at all.
    case "$m" in
        *[!\ -~]*) die "marker is not printable ASCII: '$m' — strings splits the run at it" ;;
    esac
done

# grep -F treats a newline as a pattern separator, so a multi-line marker passes
# when only one of its lines is present. Rejected above by the ASCII rule, which
# excludes newline; asserted here so the reason is recorded rather than implied.

# grep -F is a substring test. If one marker is a substring of another, the
# shorter one passes whenever the longer is present — so PROBE_1 would be
# reported found in a binary containing only PROBE_10.
for a in "${markers[@]}"; do
    for b in "${markers[@]}"; do
        [ "$a" = "$b" ] && continue
        case "$b" in
            *"$a"*) die "marker '$a' is a substring of '$b' — its result would be meaningless" ;;
        esac
    done
done

# --- the check ----------------------------------------------------------------
syms=""
cleanup() { [ -n "$syms" ] && rm -f "$syms"; }
trap cleanup EXIT INT TERM

# An explicit template, not bare `mktemp`: on macOS bare mktemp ignores TMPDIR
# and writes to the shared per-user directory, which makes the cleanup
# unobservable — you can only count a directory every process writes to.
syms=$(mktemp "${TMPDIR:-/tmp}/probe-markers.XXXXXX") || die "could not create a temporary file"

# Materialised rather than piped: `strings | grep -q` makes grep exit on the
# first match, strings then takes SIGPIPE, and under `set -o pipefail` the
# pipeline reports failure for a marker that is present. Measured at 25/25 false
# failures on a 24 MB binary. It also avoids re-scanning the binary per marker.
strings -- "$exe" > "$syms" || die "strings failed on $exe"

missing=0
for m in "${markers[@]}"; do
    set +e
    grep -Fq -- "$m" "$syms"
    rc=$?
    set -e
    case "$rc" in
        0) ;;
        1) printf 'missing probe marker: %s\n' "$m" >&2; missing=1 ;;
        *) die "grep failed (status $rc) looking for '$m'" ;;
    esac
done

[ "$missing" -eq 0 ] || exit "$EX_MISSING"
printf 'all %d probe markers present in %s\n' "${#markers[@]}" "$exe"
