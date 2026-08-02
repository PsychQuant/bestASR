#!/usr/bin/env python3
"""Regression-gate compare stage (spec regression-benchmark, #34).

stdin: {"baseline": [{corpus, language, model, metric, golden, tolerance}...],
        "measured": [{corpus, metric, error_rate, ...}...]}

Judges ACCURACY ONLY (design D1): a corpus fails when measured error_rate is
worse than golden by more than tolerance. Speed fields on measured entries are
ignored entirely. A corpus on either side without a partner on the other is a
gate error, never a silent pass. Exit 0 = all within tolerance; non-zero
otherwise. This file is the single compare implementation — the gate script
pipes into it and RegressionBaselineTests exercises it via Process.
"""
import json
import math
import sys

# Numeric sanity bounds (#134). The gate reported exit 0 on real regressions,
# which is categorically worse than a noisy log: a gate that says "pass" when it
# should say "fail" is not a weakened gate, it is an absent one still producing
# the reassuring output of a present one.
#
# The two directions are NOT symmetric, and that asymmetry is what the bounds
# encode:
#
#   * `golden` and `tolerance` are dangerous when LARGE. A huge golden makes
#     `diff = actual - golden` hugely negative; a huge tolerance makes the
#     comparison vacuous. Either way every corpus passes.
#   * `error_rate` is dangerous only when NON-FINITE. A large measured value is
#     safe — it correctly fails — so its upper bound is a garbage filter, not a
#     security boundary.
#
# Non-finite values defeat the comparison a third way: EVERY comparison against
# NaN is false, so `diff > tol` is false and the entry "passes".
# The decision is `diff = actual - golden > tol`, i.e. the gate passes anything
# at or below `golden + tolerance`. THAT SUM is the effective threshold, and the
# two fields enter it identically — they are one lever with two handles. Bounding
# only `tolerance` (as the first pass at #134 did) leaves the other handle free:
# `golden: 2.0` with an honest `tolerance: 0.02` admits every physically possible
# error rate, and the newly-rendered tolerance reads a reassuring `0.0200` on the
# rigged line, because the number that moved is not the one being rendered.
#
# So the bound that matters is on the sum. It is the only one invariant to
# trading one handle against the other; a per-field bound will always leave its
# partner as a partial substitute. The committed baseline's widest entry is
# `golden 0.1549 + tolerance 0.02 = 0.1749`, so 0.5 leaves 2.9x headroom.
#
# The error directions are not comparable, which is why this errs tight: a bound
# set too tight fails LOUDLY at `swift test`, on every PR, naming the file. A
# bound set too loose fails SILENTLY at release, as a green line.
EFFECTIVE_THRESHOLD_MAX = 0.5

# `golden` has no separate CONSTANT, deliberately — it reuses the effective
# threshold as its per-field ceiling (see `validate_numbers`). The sum bound
# already forces `golden < EFFECTIVE_THRESHOLD_MAX` (tolerance is strictly
# positive), so any separate ceiling above 0.5 can never be the guard that
# fires: mutation testing put the old `GOLDEN_MAX = 2.0` at **0 failed
# assertions** both before and after this change. It was dead either way, and a
# constant that no test can distinguish from its absence is not a guard, it is a
# comment with syntax. Removed rather than propped up with a test written to
# justify it.
#
# The surviving per-field bound on `golden` is a MESSAGE SELECTOR, not a verdict
# — it exists so an absurd golden reports as an absurd golden rather than as a
# sum violation. Judged as a verdict guard it would also score zero; that is the
# wrong instrument for it, and the test that pins it asserts the distinguishing
# message rather than the field name.
#
# (Its stated justification was wrong as well as inert: "CER can exceed 1.0 via
# insertions" describes a MEASUREMENT, which `ERROR_RATE_MAX` governs. A golden
# is a pinned expectation chosen by the maintainers. Verified that removing it
# costs nothing real: an honest golden of 0.05 against a measured 1.5 still
# fails as a REGRESSION, which is the correct verdict, rather than being
# rejected as out of bounds.)
#
# `tolerance` keeps its own ceiling because it does independent work: `golden 0`
# with `tolerance 0.4` sums to 0.4 and clears the sum bound, while 0.25 refuses
# it. `error_rate` keeps its own because the sum bound governs the baseline side
# only and never touches a measurement.
TOLERANCE_MAX = 0.25
ERROR_RATE_MAX = 100.0  # garbage filter only — a real regression must still fail loudly

# The accuracy metrics the gate knows how to judge. Same vocabulary as Swift's
# `MetricKind` and the bench validator's `metric_kind`, so an unknown value is a
# loud gate error rather than a label nobody notices (#117).
#
# The three definitions are duplicated with NO coupling test. Adding a third
# metric on the Swift side without adding it here does not just reject that
# corpus — the check below returns early, so one legitimate entry would suppress
# the verdict for every other corpus in the run.
METRICS = {"cer", "wer"}

# Every C0 control, DEL, and every C1 control, mapped to a visible escape.
# Baseline values reach stdout verbatim, and this stdout IS the CI log a human
# reads to decide whether a release is safe. A `metric` carrying CR + an ANSI
# SGR sequence can repaint the line — the reproduced payload
# "cer\x1b[32m\rFAKE ALL-PASS" renders as a green pass over the real verdict
# (#117). Escaping rather than deleting keeps the value visible, so a reader
# can still see roughly what was there.
_CONTROL_CHARS = {c: f"\\x{c:02x}" for c in range(0x20)}
_CONTROL_CHARS[0x7F] = "\\x7f"
_CONTROL_CHARS.update({c: f"\\x{c:02x}" for c in range(0x80, 0xA0)})

# Longest rejected value echoed back into the gate log. Comfortably above any
# legitimate field (the widest committed value is 6 characters) and far below
# the point where a rejected value becomes the log.
_MAX_ECHO = 120


def safe(value) -> str:
    """Neutralize ANSI/terminal control codes in a baseline-supplied value.

    Defense in depth at the render boundary: validation lives in the gate's
    worklist stage, but this script is a separate entry point that re-validates
    nothing it is handed.

    SCOPE, so callers do not over-trust it: this escapes C0, DEL and C1 —
    enough that a value cannot emit an ANSI sequence or return the cursor. It
    does NOT cover Unicode format characters (U+2028/U+2029, bidi overrides),
    which can reorder or split a line in a Unicode-aware viewer without using
    any control byte; those are unreachable through the gate today because
    corpus and language are `fullmatch`ed upstream and metric is bounded above.
    And it must be called EXPLICITLY at each interpolation — a new f-string
    added below is not covered until someone wraps it (#117).

    It also caps length. A rejected value is echoed so a human can see what was
    wrong with it, and there is no length at which that stops being the point
    and starts being a flood: a bare 400-digit integer or a multi-megabyte
    string in `golden` would otherwise be reproduced in full into a CI log
    somebody has to read (#134 verify). The head is the diagnostic part.
    """
    text = str(value).translate(_CONTROL_CHARS)
    if len(text) > _MAX_ECHO:
        return f"{text[:_MAX_ECHO]}… ({len(text)} chars)"
    return text


def _name_list(names, limit=12):
    """Render a corpus-name list without letting it become the log.

    `safe()` caps each NAME at `_MAX_ECHO`, which does nothing about the number
    of them: a meta file pinning 300 corpora would emit one 4000-character line.
    Same flood, one level up.
    """
    shown = ", ".join(safe(n) for n in names[:limit])
    if len(names) > limit:
        return f"{shown}, … (+{len(names) - limit} more)"
    return shown


def number(value, field, corpus, low, high, *, low_exclusive=False):
    """Convert and bounds-check one numeric baseline/measured field.

    Returns `(value, None)` or `(None, reason)`.

    Validation happens AFTER `float()`, deliberately. Rejecting the literal at
    parse time (`json.load(parse_constant=...)`) does not close this class:
    `{"golden": "NaN"}` is a legal JSON *string*, so `parse_constant` never
    fires, and `float("NaN")` / `float("1e999")` still produce nan / inf. The
    only reliable place to check is on the resulting float.
    """
    # `bool` is a subclass of `int`, so `float(True)` is 1.0 and a bare `true`
    # would sail through every bound below as a perfectly ordinary number. A
    # boolean is never a measurement; refusing it removes the type confusion
    # rather than letting it be laundered into one.
    if isinstance(value, bool):
        return None, f"{field} is a boolean, not a measurement (got {safe(value)!r})"
    try:
        number = float(value)
    except (TypeError, ValueError, OverflowError):
        # OverflowError is neither of the other two and had escaped: JSON has no
        # integer width limit, so a bare 400-digit literal parses to an
        # arbitrary-precision `int` and `float()` raises. It exits non-zero, so
        # it was never a bypass — but it reached the CI log as a stack trace
        # where the verdict belongs, and `regression-gate.sh` does not capture
        # stderr. Universal, not version-specific: CPython 3.11+'s 4300-digit
        # int-str cap sits far above this literal and never fires.
        return None, (f"{field} is not a number (got {safe(value)!r})")
    if not math.isfinite(number):
        # Covers nan, inf and -inf, whether they arrived as JSON literals
        # (Python's json accepts bare NaN/Infinity), as strings, or via
        # overflow from a finite-looking literal such as 1e999.
        return None, f"{field} is not a finite number (got {safe(value)!r})"
    if low_exclusive and number <= low:
        return None, f"{field} must be greater than {low:g} (got {number:g})"
    if not low_exclusive and number < low:
        return None, f"{field} must be at least {low:g} (got {number:g})"
    if number > high:
        return None, f"{field} must be at most {high:g} (got {number:g})"
    return number, None


def validate_numbers(data):
    """All numeric-field problems across both sides, as printable messages.

    Every problem is collected rather than returning on the first: a run whose
    baseline has one bad field usually has more, and reporting them one release
    at a time is its own kind of gate failure.
    """
    problems = []
    for e in data.get("baseline", []):
        corpus = e.get("corpus")
        # `high` is the effective-threshold ceiling: a golden at or above it
        # cannot be part of any acceptable (golden, tolerance) pair anyway, and
        # naming the field beats reporting it as a sum violation.
        golden, why = number(
            e.get("golden"), "golden", corpus, 0.0, EFFECTIVE_THRESHOLD_MAX)
        if why:
            problems.append((corpus, why))
        # A tolerance wide enough to absorb any plausible regression is not a
        # lenient threshold, it is a disabled gate that still prints a green line.
        tol, why = number(
            e.get("tolerance"), "tolerance", corpus, 0.0, TOLERANCE_MAX, low_exclusive=True)
        if why:
            problems.append((corpus, why))
        # The bound that actually decides whether the gate can still fail: the
        # sum is the effective threshold, so neither handle can be traded for
        # the other. Only checked when both parsed — a NaN golden has already
        # been reported above and `nan + 0.02 > 0.5` would add nothing but noise.
        if golden is not None and tol is not None and golden + tol > EFFECTIVE_THRESHOLD_MAX:
            # {:.17g} rather than {:.4f}: a value rejected for exceeding a bound
            # must not RENDER as equal to it. `0.4999999999999999 + 2e-16` is
            # refused and would print "is 0.5000, above … of 0.5" at 4dp — the
            # same defect this file exists to fix, reproduced inside the guard
            # that fixes it.
            problems.append((
                corpus,
                f"golden + tolerance is {golden + tol:.17g}, above the maximum effective "
                f"threshold of {EFFECTIVE_THRESHOLD_MAX:g} — the gate would pass any "
                f"measurement at or below that, which is not a threshold but a "
                f"disabled gate"))
    for m in data.get("measured", []):
        _, why = number(m.get("error_rate"), "error_rate", m.get("corpus"), 0.0, ERROR_RATE_MAX)
        if why:
            problems.append((m.get("corpus"), why))
    return problems


def reject_duplicate_keys(pairs):
    """`object_pairs_hook` that refuses a JSON object with a repeated key.

    Python keeps the LAST value for a duplicate key, so
    `{"golden": 0.9, "golden": 0.01}` silently becomes 0.01 — a real threshold
    hidden behind a decoy in the very file whose purpose is to be auditable by
    reading it. The duplicate-CORPUS check further down does not see this: that
    one compares entries, this is one key repeated inside a single entry.
    """
    seen = set()
    for key, _ in pairs:
        if key in seen:
            raise ValueError(f"duplicate key {key!r} in a baseline/measured entry")
        seen.add(key)
    return dict(pairs)


def main() -> int:
    try:
        data = json.load(sys.stdin, object_pairs_hook=reject_duplicate_keys)
    except ValueError as error:
        print(f"✗ GATE ERROR: cannot read the comparison input: {safe(error)}")
        print("\n✗ regression gate: 1 failure(s).")
        return 1
    failures = 0

    # A run that compared NOTHING is not a pass (#134 verify). With both sides
    # empty every loop below is a no-op, so the gate printed "all 0 corpora
    # within tolerance" and exited 0 — a fetch that produced no measurements, or
    # a worklist that silently emptied, read as "this release is safe".
    if not data.get("baseline") and not data.get("measured"):
        print("✗ GATE ERROR: nothing to compare — the baseline and the measured "
              "set are both empty. A gate that verified no corpora has not "
              "passed, it has not run.")
        print("\n✗ regression gate: 1 failure(s).")
        return 1

    # Cardinality 0 was the easy half. The gate reports on whatever it is
    # handed, and BOTH sides of that are derived from the same baseline.json —
    # the worklist stage reads it, and the assembler iterates it — so deleting
    # entries shrinks the baseline, the work list and the measured set
    # together, and "all 1 corpora within tolerance" is printed over a release
    # that verified one twelfth of what it should have. Nothing inside a stdin
    # filter can notice that; the expected set has to arrive from somewhere the
    # same edit does not reach. `regression-gate.sh` supplies it from
    # benchmarks/baseline-meta.json, the file that already carries the seeding
    # provenance — so truncating the baseline now requires a second, deliberate
    # edit to a file whose name says what it is for (#134 verify).
    expected = data.get("expected_corpora")
    if expected is None:
        # Silence must not read as a clean bill of health. A completeness check
        # that can be skipped by leaving a key out — quietly — is the same shape
        # as the hole it closes.
        print("NOTE: no expected-corpus anchor supplied — completeness of this "
              "comparison was NOT verified (this run cannot tell a full sweep "
              "from a truncated one).")
    elif not isinstance(expected, list) or not all(isinstance(c, str) for c in expected):
        # Shape-check before `set()`. Without this an int or bool raises
        # `TypeError: not iterable` and a nested list raises `unhashable type` —
        # raw tracebacks reachable from a hand-edited field in the very file this
        # guard made verdict-critical. And a bare string would be iterated
        # CHARACTER-wise, so `"ab"` would silently mean the corpora {a, b}.
        print(f"✗ GATE ERROR: the expected-corpus anchor is not a list of strings "
              f"(got {safe(type(expected).__name__)}) — the completeness check cannot "
              f"run against it")
        print("\n✗ regression gate: 1 failure(s).")
        return 1
    else:
        # `anchor_source` names the file the anchor actually came from. The path
        # is overridable (BESTASR_BASELINE_META), so hardcoding the default would
        # send a reader to a file this run never read.
        source = safe(data.get("anchor_source") or "the expected-corpus anchor")
        present = {e.get("corpus") for e in data.get("baseline", [])}
        missing = sorted(str(c) for c in set(expected) - present)
        extra = sorted(str(c) for c in present - set(expected))
        if missing:
            print(f"✗ GATE ERROR: baseline is missing {len(missing)} corpus/corpora that "
                  f"{source} pins: {_name_list(missing)} "
                  f"— a comparison over a subset is not a pass. Re-seed and update the "
                  f"provenance record, or restore the entries.")
            failures += 1
        if extra:
            print(f"✗ GATE ERROR: baseline carries {len(extra)} corpus/corpora absent from "
                  f"{source}: {_name_list(extra)} "
                  f"— an entry added without re-seeding has no provenance.")
            failures += 1
        if failures:
            print(f"\n✗ regression gate: {failures} failure(s).")
            return 1
        # A satisfied guard that prints nothing can only be observed by the
        # ABSENCE of its warning, which asks the reader to already know it
        # exists. Same argument this script makes for rendering the tolerance on
        # passing lines: auditing a pass is what the log is for.
        print(f"completeness: {len(expected)} corpora pinned by {source} — verified.")

    # `metric` is the one rendered field with no validation ANYWHERE — the
    # worklist stage checks corpus and language, nothing checks this. Unlike
    # golden/tolerance/error_rate it never passes through float(), so a hostile
    # string reaches the log intact (#117).
    for e in data.get("baseline", []):
        metric = e.get("metric")
        if metric not in METRICS:
            print(f"✗ GATE ERROR: baseline corpus '{safe(e.get('corpus'))}' has "
                  f"unknown metric {safe(metric)!r} — expected one of "
                  f"{'|'.join(sorted(METRICS))}")
            failures += 1
    if failures:
        print(f"\n✗ regression gate: {failures} failure(s).")
        return 1

    # Duplicate corpus names would silently collapse (last-wins) in the dicts
    # below — surface them as gate errors instead (#34 verify).
    for side in ("baseline", "measured"):
        names = [e["corpus"] for e in data.get(side, [])]
        for dup in sorted({n for n in names if names.count(n) > 1}):
            print(f"✗ GATE ERROR: duplicate corpus '{safe(dup)}' in {side} "
                  f"— entries would silently shadow each other")
            failures += 1
    if failures:
        print(f"\n✗ regression gate: {failures} failure(s).")
        return 1

    # Numeric sanity BEFORE any comparison (#134). Comparing with a nan or an
    # unbounded tolerance does not produce a wrong verdict so much as no verdict
    # at all, so there is nothing to salvage by continuing.
    for corpus, why in validate_numbers(data):
        print(f"✗ GATE ERROR: corpus '{safe(corpus)}': {why} — the gate cannot "
              f"judge a regression against this value")
        failures += 1
    if failures:
        print(f"\n✗ regression gate: {failures} failure(s).")
        return 1

    baseline = {e["corpus"]: e for e in data.get("baseline", [])}
    measured = {m["corpus"]: m for m in data.get("measured", [])}

    for corpus, m in measured.items():
        b = baseline.get(corpus)
        if b is None:
            print(f"✗ GATE ERROR: measured corpus '{safe(corpus)}' has no baseline entry "
                  f"— add it to benchmarks/baseline.json (never silently pass)")
            failures += 1
            continue
        # The two sides must be talking about the same yardstick (#134 verify).
        # `metric` was validated on the baseline side only, and never compared
        # across — so a WER measurement could be judged against a CER golden and
        # pass or fail on a number that means something else entirely.
        if m.get("metric") != b.get("metric"):
            print(f"✗ GATE ERROR: corpus '{safe(corpus)}' was measured as "
                  f"{safe(m.get('metric'))!r} but its baseline pins "
                  f"{safe(b.get('metric'))!r} — these are different metrics and "
                  f"cannot be compared")
            failures += 1
            continue
        golden, tol = float(b["golden"]), float(b["tolerance"])
        actual = float(m["error_rate"])
        diff = actual - golden
        if diff > tol:
            print(f"✗ REGRESSION {safe(corpus)} [{safe(b['language'])}] {safe(b['metric'])}: "
                  f"golden {golden:.4f} → measured {actual:.4f} "
                  f"(+{diff:.4f} > tolerance {tol:.4f})")
            failures += 1
        else:
            # The tolerance is rendered on the PASSING line too (#134). Auditing
            # a pass is the whole purpose of this log, and the one number that
            # could expose a rigged pass — the threshold it was judged against —
            # used to appear only on failing lines. A reader checking a green run
            # had no way to see that the bar had been lowered to meet it.
            print(f"✓ {safe(corpus)} [{safe(b['language'])}] {safe(b['metric'])}: "
                  f"golden {golden:.4f} → measured {actual:.4f} "
                  f"({diff:+.4f} ≤ tolerance {tol:.4f})")

    for corpus in baseline:
        if corpus not in measured:
            print(f"✗ GATE ERROR: baseline corpus '{safe(corpus)}' was never measured "
                  f"— gate cannot verify it (run fetch-corpora / check registration)")
            failures += 1

    if failures:
        print(f"\n✗ regression gate: {failures} failure(s). Triage: code regression, "
              f"corpus change, or upstream model-artifact drift (design D7/A3).")
        return 1
    print(f"\n✓ regression gate: all {len(measured)} corpora within tolerance "
          f"(accuracy only — speed is never gated)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
