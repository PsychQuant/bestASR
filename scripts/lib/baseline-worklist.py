#!/usr/bin/python3
"""Regression-gate baseline field-validation + work-list stage (#116, #115).

    baseline-worklist.py --emit worklist|model <baseline.json>

  --emit worklist  → stdout: one `corpus\\tlanguage` TSV record per entry
  --emit model     → stdout: the reference model name (entries[0]["model"])

CRITICAL CONTRACT — both emit modes run the COMPLETE validation pass.

This is the whole point of extracting the stage. The gate used to validate
these fields in TWO separate inline heredocs: the work-list heredoc checked
`corpus` and `language`, while the model heredoc read `entries[0]["model"]`
and printed it with NO validation at all — each stage looked only at the
fields it emitted. `model` then flowed into a path sink (MODEL_DIR → `cd`)
and into a CLI arg (`--models`), so a baseline carrying
`large-v3-turbo/../../../../../../etc` escaped the model cache root
unchallenged (#115). Validating per-mode would recreate exactly that
divergence, so validation is one pass over every field of every entry and
runs identically whichever mode is asked for.

Validation is also complete BEFORE anything is emitted: a bad field in a
later entry must not leave earlier records on stdout.

This file is the single implementation of these rules — scripts/regression-gate.sh
calls it for both stages and RegressionWorklistTests exercises it via Process,
so the tested behavior is exactly the behavior the gate runs.

Prereqs: stdlib only, /usr/bin/python3 (Xcode CLT).
"""
import argparse
import json
import re
import sys

# corpus flows into filesystem paths ($DEST/$corpus.wav) — filesystem-safe
# charset, and a leading dot is rejected so it can never name a dotfile or a
# traversal segment.
CORPUS_RE = re.compile(r"[A-Za-z0-9._-]+")

# language flows into the TSV alongside corpus (line-oriented `read` split
# downstream) AND into `--language "$language"` as a CLI arg. Without a charset
# whitelist an embedded \n forges a worklist record whose corpus field never
# passed the check above (#112). Same fullmatch discipline as corpus: a
# language tag is [a-z]{2,3} with an optional region subtag.
LANGUAGE_RE = re.compile(r"[a-z]{2,3}(-[A-Za-z0-9]+)?")

# model reaches BOTH a path sink (MODEL_DIR = "$CACHE_ROOT/openai_whisper-…",
# used as a `cd` target) and a CLI arg (`--models "$MODEL"`), so it gets the
# strictest treatment of the three (#115).
#
# The value must START with an alphanumeric, which rejects `.`, `..` and
# dotfiles outright, and contains NO `/` at all — a single path component. `..`
# is additionally rejected as a substring: the start rule already blocks `..` as
# a whole value, the substring rule additionally blocks `a..b`. Everything
# outside the charset — newline, tab, space, `;`, `|`, `&`, `$`, backtick,
# quotes, redirects, glob — is rejected by the charset alone, and
# `re.fullmatch` (unlike `$`) does not tolerate a trailing newline.
#
# No `/` branch on purpose (#126 verify): HF-style `owner/repo` names live in
# ModelGrid's `hfRepo` field, NOT in the baseline `model` field this validates.
# Both sinks reject slashes anyway — `--models` takes `family/size` (whisper/…,
# see BenchmarkRunner), and a slash in MODEL_DIR yields the unusable
# `…/openai_whisper-owner/repo`. Allowing `/` bought an empty set of working
# values while doubling reachable path depth.
#
# Net effect on the path sink: the value names a single component directly under
# the model cache root, and cannot be absolute (a leading `/` fails the
# alphanumeric-start rule). This is LEXICAL containment — it assumes the cache
# tree itself holds no hostile symlinks, since `cd` resolves those (see #129).
MODEL_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


def validate(entries):
    """Run the complete field-validation pass over every entry.

    Exits non-zero (loud, on stderr) on the first offending field. Returns
    (rows, models) where rows is the list of validated (corpus, language)
    pairs in baseline order and models the list of validated model names.
    """
    if not entries:
        sys.exit("✗ gate error: baseline is empty — nothing to gate")
    rows = []
    models = []
    seen = set()
    for e in entries:
        corpus = e["corpus"]
        if not CORPUS_RE.fullmatch(corpus) or corpus.startswith("."):
            sys.exit(f"✗ gate error: unsafe corpus name in baseline: {corpus!r}")
        if corpus in seen:
            sys.exit(f"✗ gate error: duplicate corpus in baseline: {corpus}")
        seen.add(corpus)
        language = e["language"]
        if not LANGUAGE_RE.fullmatch(language):
            sys.exit(f"✗ gate error: unsafe language in baseline: {language!r}")
        model = e.get("model")
        if not isinstance(model, str) or ".." in model or not MODEL_RE.fullmatch(model):
            sys.exit(f"✗ gate error: unsafe model in baseline: {model!r}")
        rows.append((corpus, language))
        models.append(model)
    return rows, models


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a regression baseline and emit one of its stages.")
    parser.add_argument(
        "--emit", required=True, choices=("worklist", "model"),
        help="worklist: corpus\\tlanguage TSV; model: the reference model name")
    parser.add_argument("baseline", help="path to benchmarks/baseline.json")
    # Callers MUST pass the baseline after a `--` terminator (the gate does).
    # Without it a path beginning with `-` lands in argparse's option slot, and
    # `--help` there exits 0 having validated NOTHING — a validator must have no
    # rc=0 path that skips validation (#126 verify, security lens).
    args = parser.parse_args()

    with open(args.baseline) as fh:
        entries = json.load(fh)

    # One pass, both modes, before any emission (see module docstring).
    rows, models = validate(entries)

    if args.emit == "worklist":
        for corpus, language in rows:
            print(f"{corpus}\t{language}")
    else:
        # Single fixed canary (design D2): the reference model is the first
        # entry's — every entry's model was validated above regardless.
        print(models[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
