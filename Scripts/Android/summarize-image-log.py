#!/usr/bin/env python3
"""Summarise the `[Coil]` image lines of an exported / logcat FurAffinity log.

Answers, per host, "how many image requests did we fire, how many came back
403, and were they challenges or blocks?" — plus the issuance cadence, which is
what tells a rate limit apart from a per-host verdict, and the completion span,
which is how long the burst took to drain.

    Scripts/Android/summarize-image-log.py run.log
    adb logcat -d -s fur.affinity.ui/FA | Scripts/Android/summarize-image-log.py
"""

import re
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime
from urllib.parse import urlparse

GET = re.compile(r"\[Coil\] GET request on (\S+)")
OUTCOME = re.compile(r"\[Coil\] (\S+): (succeeded on attempt|failed after) (\d+)\D*\((.*)\)\s*$")
STAMP = re.compile(r"^(\d\d-\d\d \d\d:\d\d:\d\d\.\d+)")
CODE = re.compile(r"HTTP (\d+)(?: cf-mitigated=(\S+))?")


def host(url):
    return urlparse(url).hostname or "?"


def main(lines):
    issued = []                      # (datetime|None, url) in log order
    outcomes = []                    # (datetime|None, url) in log order
    attempts = defaultdict(int)      # url -> total responses
    failures = defaultdict(list)     # url -> failure strings
    unresolved = set()               # urls that never succeeded

    for line in lines:
        stamp = STAMP.match(line)
        when = datetime.strptime(stamp.group(1), "%m-%d %H:%M:%S.%f") if stamp else None
        if m := GET.search(line):
            issued.append((when, m.group(1)))
        elif m := OUTCOME.search(line):
            url, kind, n, reasons = m.group(1), m.group(2), int(m.group(3)), m.group(4)
            outcomes.append((when, url))
            attempts[url] = n
            failures[url] = [r.strip() for r in reasons.split(",") if r.strip()]
            if kind.startswith("failed"):
                unresolved.add(url)

    if not issued:
        sys.exit("no `[Coil] GET request on` lines found")

    hosts = sorted({host(u) for _, u in issued})
    print(f"{len(issued)} requests over {len(hosts)} host(s)\n")
    print(f"{'host':<24}{'urls':>6}{'resps':>7}{'403s':>6}{'403 rate':>10}"
          f"{'urls w/403':>12}{'unresolved':>12}")
    for h in hosts:
        urls = [u for _, u in issued if host(u) == h]
        # A url with no outcome line succeeded first try: one response, no failure.
        resps = sum(max(attempts.get(u, 1), 1) for u in urls)
        codes = [CODE.search(f) for u in urls for f in failures.get(u, [])]
        n403 = sum(1 for c in codes if c and c.group(1) == "403")
        with403 = sum(1 for u in urls
                      if any((c := CODE.search(f)) and c.group(1) == "403"
                             for f in failures.get(u, [])))
        dead = sum(1 for u in urls if u in unresolved)
        print(f"{h:<24}{len(urls):>6}{resps:>7}{n403:>6}{n403 / resps:>9.0%}"
              f"{with403:>12}{dead:>12}")

    verdicts = Counter(
        (m.group(2) or "—") if (m := CODE.search(f)) and m.group(1) == "403" else None
        for fs in failures.values() for f in fs
    )
    verdicts.pop(None, None)
    if verdicts:
        print("\n403 cf-mitigated: " +
              ", ".join(f"{v}×{n}" for v, n in verdicts.most_common()))

    stamped = [w for w, _ in issued if w]
    if len(stamped) > 1:
        gaps = [(b - a).total_seconds() * 1000 for a, b in zip(stamped, stamped[1:])]
        span = (stamped[-1] - stamped[0]).total_seconds()
        print(f"\nissuance: {span:.1f} s span, gaps median {statistics.median(gaps):.0f} ms, "
              f"max {max(gaps):.0f} ms")

    # How long the burst took to drain, not just to be handed out. Only a retried or
    # failed fetch logs an outcome — a first-try success is silent — so this is the
    # first GET to the last *retry* landing, which is exactly the tail the gate
    # lengthens when a sleeping attempt holds a permit.
    done = [w for w, _ in outcomes if w]
    if stamped and done:
        drain = (max(done) - stamped[0]).total_seconds()
        overhang = (max(done) - stamped[-1]).total_seconds()
        note = (f", {overhang:.1f} s past the last GET" if overhang > 0
                else ", drained before issuance ended")
        print(f"completion: {drain:.1f} s to the last outcome "
              f"({len(outcomes)} retried/failed{note})")
    elif stamped:
        print("completion: no outcome lines — every fetch succeeded on its first attempt")

    ranks = [i for i, (_, u) in enumerate(issued) if u in unresolved or failures.get(u)]
    if ranks:
        print("issuance ranks of requests that saw a failure: " +
              ", ".join(str(r) for r in ranks[:20]) + (" …" if len(ranks) > 20 else ""))


if __name__ == "__main__":
    paths = sys.argv[1:]
    main([l for p in paths for l in open(p)] if paths else sys.stdin.readlines())
