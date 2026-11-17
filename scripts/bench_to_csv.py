#!/usr/bin/env python3
"""scripts/bench_to_csv.py — turn bench output into rows of a CSV file.

Reads what test/bench_kem.c and test/bench_sign.c print, from a log file or
stdin, so it works for any platform:

    make PLATFORM=dabao SCHEME=ml-dsa-44 run-bench          # calls this itself
    make SCHEME=ml-dsa-44 run-bench | python3 scripts/bench_to_csv.py - \\
        --csv benchmarks/qemu.csv --platform qemu --unit ticks

One row per operation (keygen / enc / dec, or keygen / sign / verify):

    platform,label,scheme,operation,iterations,min,max,avg,unit,avg_ms,date,commit

A row with the same platform, label, scheme and operation is replaced, so
re-running a benchmark updates it; use --label to keep variants apart
(e.g. "c" vs "riscv-ntt", like the hand-made benchmarks.csv).
"""

import argparse
import csv
import datetime
import os
import re
import subprocess
import sys

FIELDS = ["platform", "label", "scheme", "operation", "iterations",
          "min", "max", "avg", "unit", "avg_ms", "date", "commit"]
OP_ORDER = {"keygen": 0, "enc": 1, "sign": 1, "dec": 2, "verify": 2}


def parse(lines):
    """-> (algorithm name, iterations, {op: {"min","max","avg"}})"""
    alg, iters, ops, current = None, None, {}, None
    for raw in lines:
        line = raw.strip()
        m = re.match(r"BENCH:\s*(.+)$", line)
        if m:
            alg = m.group(1).strip()
            continue
        m = re.match(r"(?:iterations|iters):\s*(\d+)", line)
        if m:
            iters = int(m.group(1))
            continue
        # bench_kem.c:  "keygen_min: 123"
        m = re.match(r"(keygen|enc|dec|sign|verify)_(min|max|avg):\s*(\d+)$", line)
        if m:
            ops.setdefault(m.group(1), {})[m.group(2)] = int(m.group(3))
            continue
        # bench_sign.c: "keygen:" then "mn=123" / "mx=123" / "avg=123"
        m = re.match(r"(keygen|enc|dec|sign|verify)\s*:$", line)
        if m:
            current = m.group(1)
            continue
        m = re.match(r"(mn|mx|avg)=(\d+)$", line)
        if m and current:
            key = {"mn": "min", "mx": "max", "avg": "avg"}[m.group(1)]
            ops.setdefault(current, {})[key] = int(m.group(2))
    ops = {k: v for k, v in ops.items() if len(v) == 3}
    return alg, iters, ops


def git_commit():
    try:
        h = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True,
                           text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"],
                               capture_output=True, text=True).stdout.strip()
        return h + ("-dirty" if dirty else "")
    except (OSError, subprocess.CalledProcessError):
        return ""


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("log", help="bench output, or - for stdin")
    ap.add_argument("--csv", required=True)
    ap.add_argument("--platform", required=True)
    ap.add_argument("--scheme", help="default: the directory of the log file")
    ap.add_argument("--label", default="default")
    ap.add_argument("--unit", default="cycles")
    ap.add_argument("--mhz", type=float, help="clock in MHz, to fill avg_ms")
    a = ap.parse_args()

    if a.log == "-":
        lines = sys.stdin.read().splitlines()
        print("\n".join(lines))         # keep the output visible when piped
    else:
        with open(a.log, errors="replace") as f:
            lines = f.read().splitlines()

    alg, iters, ops = parse(lines)
    if not ops:
        sys.exit(f"bench_to_csv: no benchmark results found in {a.log}")
    scheme = a.scheme or (os.path.basename(os.path.dirname(os.path.abspath(a.log)))
                          if a.log != "-" else (alg or "unknown"))

    rows = []
    if os.path.exists(a.csv):
        with open(a.csv, newline="") as f:
            rows = [r for r in csv.DictReader(f)
                    if not (r["platform"] == a.platform and r["label"] == a.label
                            and r["scheme"] == scheme and r["operation"] in ops)]

    date, commit = datetime.date.today().isoformat(), git_commit()
    for op, v in ops.items():
        avg_ms = f"{v['avg'] / (a.mhz * 1000):.3f}" if a.mhz else ""
        rows.append(dict(platform=a.platform, label=a.label, scheme=scheme, operation=op,
                         iterations=iters or "", min=v["min"], max=v["max"], avg=v["avg"],
                         unit=a.unit, avg_ms=avg_ms, date=date, commit=commit))

    rows.sort(key=lambda r: (r["platform"], r["label"], r["scheme"],
                             OP_ORDER.get(r["operation"], 9), r["operation"]))
    os.makedirs(os.path.dirname(a.csv) or ".", exist_ok=True)
    with open(a.csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)

    print(f"[bench_to_csv] {scheme} ({alg}): "
          + ", ".join(f"{op} avg {v['avg']}" for op, v in ops.items())
          + f" {a.unit} -> {a.csv}")


if __name__ == "__main__":
    main()
