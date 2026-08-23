#!/usr/bin/env python3
"""Compare cold image runs, arm by arm, on top of `summarize-image-log.py`.

Never judge a change here on one run: the run-to-run spread within a single
emulator session reaches 0%-97% on the same host, and the session's own drift is
large and monotone. Measure A-B-A — shipping, change, shipping — and read the
change against *both* shipping arms (Android/docs/images.md).

    Scripts/Android/compare-image-runs.py run-*.log
    Scripts/Android/compare-image-runs.py --arm A1 a1-*.log --arm B b-*.log --arm A2 a2-*.log
"""

import re
import statistics
import subprocess
import sys
from pathlib import Path

SUMMARIZE = Path(__file__).with_name("summarize-image-log.py")

FA_HOST = re.compile(r"^([at]\.furaffinity\.net)\s+(.*)$")
ISSUANCE = re.compile(r"issuance: ([\d.]+) s span, gaps median (\d+) ms, max (\d+) ms")
COMPLETION = re.compile(r"completion: ([\d.]+) s to the last outcome \((\d+) ")
SPLIT = re.compile(r"^(\d+)/(\d+)$")
CFPAGE = re.compile(r"Cloudflare challenge on URLSession")

# name, width, how to render one run, how to render an arm's median.
COLUMNS = [
    ("resps", 6, "{resps:.0f}", "{resps:.0f}"),
    ("403s", 6, "{n403:.0f}", "{n403:.0f}"),
    ("403%", 6, "{rate:.0f}%", "{rate:.0f}%"),
    ("lost", 6, "{lost:.0f}", "{lost:.1f}"),
    ("conns", 6, "{conns:.0f}", "{conns:.1f}"),
    ("403/new", 8, "{new403:.0%}", "{new403:.0%}"),
    ("403/reuse", 10, "{reused403:.0%}", "{reused403:.0%}"),
    ("issue s", 8, "{issuance:.1f}", "{issuance:.1f}"),
    ("drain s", 8, "{drain:.1f}", "{drain:.1f}"),
    ("cfpage", 7, "{cfpage:.0f}", "{cfpage:.0f}"),
]
KEYS = ("resps", "n403", "rate", "lost", "conns", "new403", "reused403",
        "issuance", "drain", "cfpage")


def parse(path):
    """One run's numbers, summed over the FA image hosts."""
    out = subprocess.run([sys.executable, SUMMARIZE, path],
                         capture_output=True, text=True).stdout
    run = dict(name=Path(path).stem, resps=0, n403=0, lost=0, conns=0,
               new403=0, new=0, reused403=0, reused=0,
               issuance=0.0, drain=0.0, cfpage=0)

    # Both per-host tables name the same hosts and are told apart by shape: the
    # first is all integers, the connections one carries a float (resps/conn) in
    # its third column.
    for line in out.splitlines():
        if not (m := FA_HOST.match(line)):
            continue
        f = m.group(2).split()
        if "." in f[2]:
            run["conns"] += int(f[0])
            # `403 on new` / `403 on reused` print as "5/7 71%"; a host that saw
            # neither prints an em dash.
            for hits, key in ((f[3], "new"), (f[5], "reused")):
                if s := SPLIT.match(hits):
                    run[key + "403"] += int(s.group(1))
                    run[key] += int(s.group(2))
        else:
            run["resps"] += int(f[1])
            run["n403"] += int(f[2])
            run["lost"] += int(f[5])

    if m := ISSUANCE.search(out):
        run["issuance"] = float(m.group(1))
    if m := COMPLETION.search(out):
        run["drain"] = float(m.group(1))
    # Issuance is the honest fallback when nothing logged a dated outcome.
    run["drain"] = run["drain"] or run["issuance"]
    run["cfpage"] = len(CFPAGE.findall(Path(path).read_text()))

    run["rate"] = 100 * run["n403"] / max(run["resps"], 1)
    run["new403"] = run["new403"] / max(run["new"], 1)
    run["reused403"] = run["reused403"] / max(run["reused"], 1)
    return run


def header():
    return f"{'run':<16}" + "".join(f"{name:>{w}}" for name, w, _, _ in COLUMNS)


def row(label, values, median=False):
    cells = "".join(f"{(f2 if median else f1).format(**values):>{w}}"
                    for _, w, f1, f2 in COLUMNS)
    return f"{label:<16}{cells}"


def main(arms):
    print(header())
    medians = {}
    for arm, paths in arms:
        runs = [parse(p) for p in paths]
        if len(arms) > 1:
            print(f"-- {arm} " + "-" * (len(header()) - len(arm) - 4))
        for run in runs:
            print(row(run["name"], run))
        medians[arm] = {k: statistics.median(r[k] for r in runs) for k in KEYS}
        print(row(f"MEDIAN {arm}" if len(arms) > 1 else "MEDIAN",
                  medians[arm], median=True))

    if len(medians) > 1:
        print("\n" + header().replace("run ", "arm ", 1))
        for arm, med in medians.items():
            print(row(arm, med, median=True))


def parse_args(argv):
    """`--arm NAME log…` groups; bare paths before the first one are one arm."""
    arms = []
    expecting_name = False
    for arg in argv:
        if arg == "--arm":
            expecting_name = True
        elif expecting_name:
            arms.append((arg, []))
            expecting_name = False
        else:
            if not arms:
                arms.append(("runs", []))
            arms[-1][1].append(arg)
    return [a for a in arms if a[1]]


if __name__ == "__main__":
    args = parse_args(sys.argv[1:])
    if not args:
        sys.exit("usage: compare-image-runs.py [--arm NAME] run.log…")
    main(args)
