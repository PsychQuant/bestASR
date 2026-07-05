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


def main() -> int:
    data = json.load(sys.stdin)
    baseline = {e["corpus"]: e for e in data.get("baseline", [])}
    measured = {m["corpus"]: m for m in data.get("measured", [])}
    failures = 0

    for corpus, m in measured.items():
        b = baseline.get(corpus)
        if b is None:
            print(f"✗ GATE ERROR: measured corpus '{corpus}' has no baseline entry "
                  f"— add it to benchmarks/baseline.json (never silently pass)")
            failures += 1
            continue
        golden, tol = float(b["golden"]), float(b["tolerance"])
        actual = float(m["error_rate"])
        diff = actual - golden
        if diff > tol:
            print(f"✗ REGRESSION {corpus} [{b['language']}] {b['metric']}: "
                  f"golden {golden:.4f} → measured {actual:.4f} "
                  f"(+{diff:.4f} > tolerance {tol:.4f})")
            failures += 1
        else:
            print(f"✓ {corpus} [{b['language']}] {b['metric']}: "
                  f"golden {golden:.4f} → measured {actual:.4f} ({diff:+.4f})")

    for corpus in baseline:
        if corpus not in measured:
            print(f"✗ GATE ERROR: baseline corpus '{corpus}' was never measured "
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
