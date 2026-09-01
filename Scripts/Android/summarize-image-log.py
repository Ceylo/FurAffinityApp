#!/usr/bin/env python3
"""Summarise the `[Coil]` image and `[HTTP]` page lines of a FurAffinity log.

Answers, per host, "how many image requests did we fire, how many came back
403, and were they challenges or blocks?" — plus the issuance cadence, which is
what tells a rate limit apart from a per-host verdict, and the completion span,
which is how long the burst took to drain.

Then the causal variable itself: how many *connections* the burst opened, when
it opened them, and the 403 rate split by whether the response rode a fresh
connection or a reused one. Cloudflare judges the connection, so that split is
the direct test of the whole model — see Android/docs/images.md. Logs predating
`conn=` in the `[Coil]` lines simply omit that section.

Page fetches feed the *same* tables — they ride the same client and the same
pool, so a per-host 403 split covers them for free. Two sections are theirs
alone: a table keyed by connection id, which is where coalescing shows up (one
id serving www. *and* t./a. means the two pipelines share a connection), and a
`[CFREPAIR]` section, which is how you tell a repair that worked from one that
did not.

    Scripts/Android/summarize-image-log.py run.log
    Scripts/Android/logs.sh -d | Scripts/Android/summarize-image-log.py
"""

import re
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime
from urllib.parse import urlparse

GET = re.compile(r"\[Coil\] GET request on (\S+)")
OUTCOME = re.compile(r"\[Coil\] (\S+): (succeeded on attempt|failed after) (\d+)\D*\((.*)\)\s*$")
# The per-fetch success line, which only a build carrying the connection instrument
# emits: `[Coil] <url>: 200 conn=<id> new=<bool> <ms>ms`.
SUCCESS = re.compile(r"\[Coil\] (\S+): (\d{3}) conn=(-?\d+) new=(true|false) (-?\d+)ms")
# A page fetch, in the same token shapes:
# `[HTTP] GET <url> → 200 h2 conn=<id> new=false 214ms`
PAGE = re.compile(
    r"\[HTTP\] (?:GET|POST) (\S+) → (\d{3}) (\S+) conn=(-?\d+|-) new=(true|false) (-?\d+)ms"
)
ARM = re.compile(r"\[HTTP\] transport=(\S+) h2=(\S+)")
# The image pipeline names its protocol once per host, not per connection.
NEGOTIATED = re.compile(r"\[Coil\] (\S+) negotiated (\S+)")
# The repair vocabulary. A repair worked iff a `challenge` is followed by a
# `retry → 200` and no further challenge at the next epoch.
REPAIR = re.compile(r"\[CFREPAIR\] (\S+)(.*)")
STAMP = re.compile(r"^(\d\d-\d\d \d\d:\d\d:\d\d\.\d+)")
CODE = re.compile(r"HTTP (\d+)(?: cf-mitigated=(\S+))?")
# Every failed attempt carries its own draw, appended by FACoilBridge.
CONN = re.compile(r"conn=(-?\d+) new=(true|false)")


def host(url):
    return urlparse(url).hostname or "?"


def main(lines):
    issued = []                      # (datetime|None, url) in log order
    outcomes = []                    # (datetime|None, url) in log order
    attempts = defaultdict(int)      # url -> total responses
    failures = defaultdict(list)     # url -> failure strings
    unresolved = set()               # urls that never succeeded
    draws = []                       # (url, conn id, opened it?, code, attempt, when)
    successes = 0                    # per-fetch 200 lines, absent from older logs
    attempt_of = defaultdict(int)    # url -> attempts drawn since its last GET
    issued_at = {}                   # url -> when its current fetch was handed out
    protocol_of = {}                 # conn id -> the protocol it negotiated
    host_protocol = {}               # host -> protocol, for the image pipeline
    arm = None                       # the run's self-declared transport
    repairs = Counter()              # [CFREPAIR] verb -> count
    resolutions = []                 # seconds each solve took
    parks = []                       # ("timed out"|"refused", …)

    def draw(url, text, code):
        """Record the connection one attempt rode, if the log names it.

        Attempts arrive in order: a fetch logs its failed ones inside the retry line,
        then its winning one. A re-fetch of the same URL restarts the count at its
        own `GET request` line.
        """
        if m := CONN.search(text):
            attempt_of[url] += 1
            draws.append((url, int(m.group(1)), m.group(2) == "true", code,
                          attempt_of[url], issued_at.get(url)))

    for line in lines:
        stamp = STAMP.match(line)
        when = datetime.strptime(stamp.group(1), "%m-%d %H:%M:%S.%f") if stamp else None
        if m := GET.search(line):
            issued.append((when, m.group(1)))
            attempt_of[m.group(1)] = 0
            issued_at[m.group(1)] = when
        elif m := OUTCOME.search(line):
            url, kind, n, reasons = m.group(1), m.group(2), int(m.group(3)), m.group(4)
            outcomes.append((when, url))
            attempts[url] = n
            failures[url] = [r.strip() for r in reasons.split(",") if r.strip()]
            if kind.startswith("failed"):
                unresolved.add(url)
            for reason in failures[url]:
                code = int(c.group(1)) if (c := CODE.search(reason)) else None
                draw(url, reason, code)
        elif m := SUCCESS.search(line):
            outcomes.append((when, m.group(1)))
            successes += 1
            draw(m.group(1), line, int(m.group(2)))
        elif m := PAGE.search(line):
            # A page fetch is one response, always: FAHTTPDataSource logs a line per
            # exchange, so each is its own draw with no retry line to unpack.
            url, code = m.group(1), int(m.group(2))
            issued.append((when, url))
            outcomes.append((when, url))
            attempts[url] = attempts.get(url, 0) + 1
            if code == 403:
                failures[url].append(f"HTTP 403 cf-mitigated=challenge{m.group(0)[m.group(0).index(' conn='):]}")
            if m.group(4) != "-":
                attempt_of[url] += 1
                draws.append((url, int(m.group(4)), m.group(5) == "true", code,
                              attempt_of[url], when))
                protocol_of[int(m.group(4))] = m.group(3)
        elif m := NEGOTIATED.search(line):
            host_protocol[m.group(1)] = m.group(2)
        elif m := ARM.search(line):
            arm = f"transport={m.group(1)} h2={m.group(2)}"
        elif m := REPAIR.search(line):
            verb, rest = m.group(1), m.group(2)
            repairs[verb] += 1
            if verb == "resolution" and (d := re.search(r"took ([\d.]+)", rest)):
                resolutions.append(float(d.group(1)))
            if verb == "retry":
                repairs["retry 200" if "→ 200" in rest else "retry still challenged"] += 1
            if verb == "image" and "timed out" in rest:
                parks.append("timed out")
            if verb == "image" and "refused" in rest:
                parks.append("refused")

    if not issued:
        sys.exit("no `[Coil] GET request on` or `[HTTP]` lines found")

    if arm:
        print(f"arm: {arm}\n")
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
        # Without the per-fetch 200 line only retried and failed fetches are dated, so
        # on an older log this span is the tail rather than the whole burst.
        kind = "completed" if successes else "retried/failed"
        print(f"completion: {drain:.1f} s to the last outcome "
              f"({len(outcomes)} {kind}{note})")
    elif stamped:
        print("completion: no outcome lines — every fetch succeeded on its first attempt")

    if draws:
        # The direct test of the per-connection model. If 403s do not concentrate on
        # `new=true`, the model is wrong at this granularity and nothing built on it
        # (the launch ramp, HTTP/2) can be expected to help.
        print(f"\n{'host':<24}{'conns':>7}{'draws':>7}{'resps/conn':>12}"
              f"{'403 on new':>15}{'403 on reused':>16}")

        def rate(rows):
            if not rows:
                return "—"
            n403 = sum(1 for d in rows if d[3] == 403)
            return f"{n403}/{len(rows)} {n403 / len(rows):.0%}"

        for h in hosts:
            rows = [d for d in draws if host(d[0]) == h]
            if not rows:
                continue
            ids = {d[1] for d in rows}
            fresh = [d for d in rows if d[2]]
            print(f"{h:<24}{len(ids):>7}{len(fresh):>7}"
                  f"{len(rows) / len(ids):>12.1f}"
                  f"{rate(fresh):>15}{rate([d for d in rows if not d[2]]):>16}")

        # When the burst opened its connections, in seconds from the first GET — the
        # ramp's whole claim is that these go serial instead of simultaneous. First
        # attempts only, dated by the URL's `GET request` line: that one is logged
        # inside the concurrency permit immediately before the blocking call, so it is
        # when the draw went out. A retry's draw has no timestamp of its own, and the
        # table above already counts it.
        if stamped:
            for h in hosts:
                offsets = sorted((w - stamped[0]).total_seconds()
                                 for url, _, is_new, _, n, w in draws
                                 if host(url) == h and is_new and n == 1 and w)
                if offsets:
                    print(f"  {h} opened {len(offsets)} at " +
                          " ".join(f"{o:.1f}" for o in offsets) + " s")

    # Appended, never woven into the two tables above: compare-image-runs.py scrapes
    # those by shape.
    #
    # The coalescing answer. One connection id serving www. *and* t./a. means the page
    # and image pipelines share a connection — only possible under h2, and only
    # comparable at all because both now come from one client's identityHashCode.
    if draws:
        by_conn = defaultdict(list)
        for row in draws:
            by_conn[row[1]].append(row)
        print(f"\n{'conn':>12}{'proto':>10}{'resps':>7}{'403s':>6}  hosts")
        for conn, rows in sorted(by_conn.items(), key=lambda kv: -len(kv[1])):
            names = sorted({host(r[0]) for r in rows})
            n403 = sum(1 for r in rows if r[3] == 403)
            proto = protocol_of.get(conn) or host_protocol.get(names[0], "?")
            print(f"{conn:>12}{proto:>10}{len(rows):>7}{n403:>6}  " + ",".join(names))
        shared = [c for c, rows in by_conn.items() if len({host(r[0]) for r in rows}) > 1]
        print(f"{len(by_conn)} connections, {len(shared)} serving more than one host")

    if repairs:
        print("\n[CFREPAIR]")
        print(f"  challenges {repairs['challenge']}, "
              f"evicted {repairs['evicted']}, skipped {repairs['evict skipped']}")
        print(f"  resolutions {repairs['resolution']}"
              + (f", median {statistics.median(resolutions):.1f} s, "
                 f"worst {max(resolutions):.1f} s" if resolutions else ""))
        print(f"  post-repair retries: {repairs['retry 200']} → 200, "
              f"{repairs['retry still challenged']} still challenged")
        if parks:
            print(f"  image parks ended early: " + ", ".join(parks))

    ranks = [i for i, (_, u) in enumerate(issued) if u in unresolved or failures.get(u)]
    if ranks:
        print("issuance ranks of requests that saw a failure: " +
              ", ".join(str(r) for r in ranks[:20]) + (" …" if len(ranks) > 20 else ""))


if __name__ == "__main__":
    paths = sys.argv[1:]
    main([l for p in paths for l in open(p)] if paths else sys.stdin.readlines())
