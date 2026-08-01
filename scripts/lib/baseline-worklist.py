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
# A segment is corpus-safe but must additionally START with an alphanumeric,
# which rejects `.`, `..` and dotfiles as a whole segment. At most ONE internal
# `/` is allowed so plausible HF-style `owner/repo` names still work, while
# `a/b/c` and any deeper path do not. `..` anywhere is rejected outright below
# (belt and braces: the segment rule already blocks `..` as a segment, the
# substring rule additionally blocks `a..b`). Everything outside the charset —
# newline, tab, space, `;`, `|`, `&`, `$`, backtick, quotes, redirects, glob —
# is rejected by the charset alone, and `re.fullmatch` (unlike `$`) does not
# tolerate a trailing newline.
#
# Net effect on the path sink: the value can only ever name something one level
# INSIDE the model cache root; it can never escape it and can never be absolute
# (a leading `/` fails the alphanumeric-start rule).
MODEL_SEGMENT = r"[A-Za-z0-9][A-Za-z0-9._-]*"
MODEL_RE = re.compile(rf"{MODEL_SEGMENT}(/{MODEL_SEGMENT})?")


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
