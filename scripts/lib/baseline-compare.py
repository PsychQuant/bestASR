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
import sys

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
    """
    return str(value).translate(_CONTROL_CHARS)


def main() -> int:
    data = json.load(sys.stdin)
    failures = 0

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

    baseline = {e["corpus"]: e for e in data.get("baseline", [])}
    measured = {m["corpus"]: m for m in data.get("measured", [])}

    for corpus, m in measured.items():
        b = baseline.get(corpus)
        if b is None:
            print(f"✗ GATE ERROR: measured corpus '{safe(corpus)}' has no baseline entry "
                  f"— add it to benchmarks/baseline.json (never silently pass)")
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
            print(f"✓ {safe(corpus)} [{safe(b['language'])}] {safe(b['metric'])}: "
                  f"golden {golden:.4f} → measured {actual:.4f} ({diff:+.4f})")

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
