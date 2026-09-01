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
from collections import Counter
import subprocess
import sys
from pathlib import Path

SUMMARIZE = Path(__file__).with_name("summarize-image-log.py")

FA_HOST = re.compile(r"^([at]\.furaffinity\.net)\s+(.*)$")
ISSUANCE = re.compile(r"issuance: ([\d.]+) s span, gaps median (\d+) ms, max (\d+) ms")
COMPLETION = re.compile(r"completion: ([\d.]+) s to the last outcome \((\d+) ")
SPLIT = re.compile(r"^(\d+)/(\d+)$")
# A challenged *response*, in either pipeline. `[CFREPAIR] challenge <url>` is what
# both paths log now; the old spelling stays so archived runs still parse.
CFPAGE = re.compile(r"\[CFREPAIR\] challenge https://www\.|Cloudflare challenge on URLSession")
CFIMG = re.compile(r"\[CFREPAIR\] challenge https://[ta]\.")
REPAIRED = re.compile(r"\[CFREPAIR\] evicted ")
RETRY_OK = re.compile(r"\[CFREPAIR\] retry \S+ → 200")
RETRY_BAD = re.compile(r"\[CFREPAIR\] retry \S+ → still challenged")
RESOLUTION = re.compile(r"\[CFREPAIR\] resolution took ([\d.]+)")
ARM = re.compile(r"\[HTTP\] transport=(\S+) h2=(\S+)")
PAGES = re.compile(r"\[HTTP\] (?:GET|POST) ")
CONNS = re.compile(r"(\d+) connections, \d+ serving more than one host")
SHARED = re.compile(r"\d+ connections, (\d+) serving more than one host")

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
    # Appended, never inserted: the two tables above are scraped by shape.
    ("pages", 6, "{pages:.0f}", "{pages:.0f}"),
    ("cfimg", 6, "{cfimg:.0f}", "{cfimg:.0f}"),
    ("repair", 7, "{repair:.0f}", "{repair:.1f}"),
    ("fixed%", 7, "{fixed}", "{fixed}"),
    ("shared", 7, "{shared:.0f}", "{shared:.1f}"),
    ("solve s", 8, "{solve:.1f}", "{solve:.1f}"),
]
KEYS = ("resps", "n403", "rate", "lost", "conns", "new403", "reused403",
        "issuance", "drain", "cfpage", "pages", "cfimg", "repair", "shared", "solve")
# `fixed%` is a string, so it gets the modal value across an arm rather than a median.
STRING_KEYS = ("fixed",)


def parse(path):
    """One run's numbers, summed over the FA image hosts."""
    out = subprocess.run([sys.executable, SUMMARIZE, path],
                         capture_output=True, text=True).stdout
    run = dict(name=Path(path).stem, resps=0, n403=0, lost=0, conns=0,
               new403=0, new=0, reused403=0, reused=0,
               issuance=0.0, drain=0.0, cfpage=0,
               pages=0, cfimg=0, repair=0, fixed=0.0, shared=0, solve=0.0, arm="")

    # Both per-host tables name the same hosts and are told apart by shape: the
    # first is all integers, the connections one carries a float (resps/conn) in
    # its third column.
    for line in out.splitlines():
        if not (m := FA_HOST.match(line)):
            continue
        f = m.group(2).split()
        if "." in f[2]:
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

    text = Path(path).read_text()
    run["cfpage"] = len(CFPAGE.findall(text))
    run["cfimg"] = len(CFIMG.findall(text))
    run["pages"] = len(PAGES.findall(text))
    run["repair"] = len(REPAIRED.findall(text))
    if m := ARM.search(text):
        run["arm"] = f"{m.group(1)} h2={m.group(2)}"
    # Did a repair actually fix anything? The post-repair retry is the only honest
    # answer: a challenge that leads to a 200 was repaired, one that leads to another
    # challenge was not.
    ok, bad = len(RETRY_OK.findall(text)), len(RETRY_BAD.findall(text))
    # An em dash rather than 0% when nothing was repaired: "no repairs" and "every
    # repair failed" are opposite results and must not print the same.
    run["fixed"] = f"{100 * ok // (ok + bad)}%" if ok + bad else "—"
    solves = [float(x) for x in RESOLUTION.findall(text)]
    run["solve"] = statistics.median(solves) if solves else 0.0

    # `conns` changes meaning: distinct connection ids across *both* pipelines, which
    # is the honest count once they share a client. Taken from the summariser's own
    # connection table so the two can never disagree.
    if m := CONNS.search(out):
        run["conns"] = int(m.group(1))
    if m := SHARED.search(out):
        run["shared"] = int(m.group(1))

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


LEGEND = """\
cfpage/cfimg  challenged responses the pipeline could not redraw its way out of and
              handed to the repair — not every 403 (an image that recovers inside its
              own retries never reports one).
repair        evictions actually performed. Compare with cfpage+cfimg: the epoch guard
              means many challenged workers should share one eviction.
fixed%        post-repair retries that came back 200. This is the only honest answer to
              "did the repair work"; — means nothing was repaired.
shared        connections serving more than one host, i.e. coalescing. Only h2 can.
solve s       median Cloudflare resolution time."""


def main(arms):
    print(header())
    medians, worsts = {}, {}
    for arm, paths in arms:
        runs = [parse(p) for p in paths]
        declared = {r["arm"] for r in runs if r["arm"]}
        if len(arms) > 1:
            label = arm + (f" [{', '.join(sorted(declared))}]" if declared else "")
            print(f"-- {label} " + "-" * max(len(header()) - len(label) - 4, 3))
        for run in runs:
            print(row(run["name"], run))
        medians[arm] = {k: statistics.median(r[k] for r in runs) for k in KEYS}
        for k in STRING_KEYS:
            medians[arm][k] = Counter(r[k] for r in runs).most_common(1)[0][0]
        # Runs here are strongly bimodal — a session is either challenging almost
        # nothing or challenging almost everything — so the median describes the good
        # mode and says nothing about the bad one, which is the mode that loses images.
        worsts[arm] = {k: max(r[k] for r in runs) for k in KEYS}
        # The worst `fixed%` is the lowest one — it is the only column where less is worse.
        for k in STRING_KEYS:
            worsts[arm][k] = min((r[k] for r in runs),
                                 key=lambda v: 101 if v == "—" else int(v.rstrip("%")))
        suffix = f" {arm}" if len(arms) > 1 else ""
        print(row("MEDIAN" + suffix, medians[arm], median=True))
        print(row("WORST" + suffix, worsts[arm], median=True))

    if len(medians) > 1:
        for label, table in (("median", medians), ("worst run", worsts)):
            print(f"\n{label}\n" + header().replace("run ", "arm ", 1))
            for arm, values in table.items():
                print(row(arm, values, median=True))
        print("\n" + LEGEND)


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
