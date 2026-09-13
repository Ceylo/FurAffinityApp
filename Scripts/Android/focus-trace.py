#!/usr/bin/env python3
"""Cut a Perfetto trace down to one app's signposts, and summarise them.

A system trace holds every process on the device, and the app's own ATrace
sections are mostly the framework's and Compose's. This keeps only:

- the app's processes, their threads (named from the scheduler data, which the
  process tree lacks) and their memory counters;
- the app's sections whose name starts with one of the prefixes — by default
  our signposts, which OSCompat names `<category>: <name>`.

Everything else — scheduling, other processes, the frame timeline — is dropped,
so the output opens in https://ui.perfetto.dev as one process with a handful of
tracks. The full trace stays next to it for when the context matters.

    Scripts/Android/focus-trace.py fa.pftrace <app id> -o signposts.pftrace
    Scripts/Android/focus-trace.py fa.pftrace <app id> --prefix "Compose:" --prefix "FAKit: "

The summary (stdout) lists each signpost's count, total, median and max, and the
threads it ran on. Durations are wall time from begin to end, not CPU time.

Only the fields read here are decoded, straight from the wire format, so this
needs no protobuf package. Field numbers are from Perfetto's
protos/perfetto/trace/perfetto_trace.proto.
"""

import argparse
import collections
import statistics
import sys

DEFAULT_PREFIXES = ["FAKit: ", "FAPages: "]

# TracePacket
PACKET = 1            # Trace.packet
FTRACE_EVENTS = 1     # TracePacket.ftrace_events
PROCESS_TREE = 2
PROCESS_STATS = 9
TIMESTAMP = 8
FRAME_TIMELINE = 76
# FtraceEventBundle
BUNDLE_EVENT = 2
BUNDLE_COMPACT_SCHED = 4
# FtraceEvent
EVENT_TIMESTAMP = 1
EVENT_PID = 2         # the thread id
EVENT_PRINT = 3
PRINT_BUF = 2
# CompactSched
SCHED_INTERN_TABLE = 5
SCHED_SWITCH_NEXT_PID = 3
SCHED_SWITCH_NEXT_COMM = 6
SCHED_WAKING_PID = 8
SCHED_WAKING_COMM = 11
# ProcessTree
TREE_PROCESS = 1
TREE_THREAD = 2
PROCESS_PID = 1
PROCESS_CMDLINE = 3
THREAD_TID = 1
THREAD_NAME = 2
THREAD_TGID = 3
# ProcessStats
STATS_PROCESS = 1
STATS_PID = 1
STATS_VM_RSS_KB = 3


# --- wire format -------------------------------------------------------------

def read_varint(buf, i):
    result = shift = 0
    while True:
        byte = buf[i]
        i += 1
        result |= (byte & 0x7F) << shift
        if byte < 0x80:
            return result, i
        shift += 7


def fields(buf, start=0, end=None):
    """Yield (field, wire type, value, raw start, raw end). A length-delimited
    value is its (start, end) range."""
    i = start
    end = len(buf) if end is None else end
    while i < end:
        raw_start = i
        key, i = read_varint(buf, i)
        field, wire = key >> 3, key & 7
        if wire == 0:
            value, i = read_varint(buf, i)
        elif wire == 2:
            length, i = read_varint(buf, i)
            value = (i, i + length)
            i += length
        elif wire == 1:
            value = int.from_bytes(buf[i:i + 8], "little")
            i += 8
        elif wire == 5:
            value = int.from_bytes(buf[i:i + 4], "little")
            i += 4
        else:
            raise ValueError(f"unsupported wire type {wire} at byte {raw_start}")
        yield field, wire, value, raw_start, i


def packed_varints(buf, span):
    i, end = span
    while i < end:
        value, i = read_varint(buf, i)
        yield value


def int32(value):
    return value - (1 << 64) if value >= 1 << 63 else value


def encode_varint(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def length_delimited(field, payload):
    return encode_varint(field << 3 | 2) + encode_varint(len(payload)) + payload


def text(buf, span):
    return buf[span[0]:span[1]].decode("utf-8", "replace")


def submessage(buf, span):
    """{field: [value, …]} of a message, strings left as spans."""
    out = collections.defaultdict(list)
    for field, _, value, _, _ in fields(buf, *span):
        out[field].append(value)
    return out


# --- pass 1: who is the app, and what are its threads called ------------------

def survey(buf, app_id):
    app_pids = set()
    thread_names = {}
    for field, wire, packet, _, _ in fields(buf):
        if field != PACKET or wire != 2:
            continue
        for pfield, pwire, pvalue, _, _ in fields(buf, *packet):
            if pwire != 2:
                continue
            if pfield == PROCESS_TREE:
                for tfield, twire, tvalue, _, _ in fields(buf, *pvalue):
                    if tfield != TREE_PROCESS or twire != 2:
                        continue
                    process = submessage(buf, tvalue)
                    cmdline = [text(buf, s) for s in process.get(PROCESS_CMDLINE, [])]
                    # The app itself, not its `:remote` services or the WebView sandbox.
                    if cmdline and cmdline[0] == app_id and process.get(PROCESS_PID):
                        app_pids.add(int32(process[PROCESS_PID][0]))
            elif pfield == FTRACE_EVENTS:
                for bfield, bwire, bvalue, _, _ in fields(buf, *pvalue):
                    if bfield == BUNDLE_COMPACT_SCHED and bwire == 2:
                        collect_comms(buf, bvalue, thread_names)
    # ART names the main thread after the package's last 15 bytes: "droid_profiling".
    for pid in app_pids:
        thread_names[pid] = "main"
    return app_pids, thread_names


def collect_comms(buf, span, names):
    sched = submessage(buf, span)
    table = [text(buf, s) for s in sched.get(SCHED_INTERN_TABLE, [])]
    for pid_field, comm_field in ((SCHED_SWITCH_NEXT_PID, SCHED_SWITCH_NEXT_COMM),
                                  (SCHED_WAKING_PID, SCHED_WAKING_COMM)):
        pids = [int32(v) for s in sched.get(pid_field, []) for v in packed_varints(buf, s)]
        comms = [v for s in sched.get(comm_field, []) for v in packed_varints(buf, s)]
        for pid, comm in zip(pids, comms):
            if comm < len(table):
                names[pid] = table[comm]


# --- pass 2: rewrite ------------------------------------------------------------

class Sections:
    """Pairs ATrace B/E markers per thread, deciding once at B whether to keep."""

    def __init__(self, app_pids, prefixes):
        self.app_pids = app_pids
        self.prefixes = prefixes
        self.stacks = collections.defaultdict(list)
        self.durations = collections.defaultdict(list)   # name → [ns]
        self.threads = collections.defaultdict(collections.Counter)
        self.unclosed = collections.Counter()

    def keep(self, tid, timestamp, marker):
        if marker.startswith("B|"):
            parts = marker.rstrip("\n").split("|", 2)
            name = parts[2] if len(parts) == 3 else ""
            try:
                tgid = int(parts[1])
            except (IndexError, ValueError):
                tgid = -1
            kept = tgid in self.app_pids and any(name.startswith(p) for p in self.prefixes)
            self.stacks[tid].append((kept, name, timestamp))
            return kept
        if marker.startswith("E|"):
            if not self.stacks[tid]:
                return False
            kept, name, begin = self.stacks[tid].pop()
            if kept:
                self.durations[summary_name(name)].append(timestamp - begin)
                self.threads[summary_name(name)][tid] += 1
            return kept
        return False

    def finish(self):
        for stack in self.stacks.values():
            for kept, name, _ in stack:
                if kept:
                    self.unclosed[summary_name(name)] += 1


def summary_name(section):
    # "<category>: <name>: <message>" groups under "<category>: <name>".
    parts = section.split(": ")
    return ": ".join(parts[:2])


def rewrite(buf, app_pids, thread_names, sections):
    out = bytearray()
    rss = []   # (timestamp, pid, kb)
    for field, wire, packet, raw_start, raw_end in fields(buf):
        if field != PACKET or wire != 2:
            out += buf[raw_start:raw_end]
            continue
        timestamp = None
        body = bytearray()
        drop_packet = False
        for pfield, pwire, pvalue, pstart, pend in fields(buf, *packet):
            if pfield == TIMESTAMP and pwire == 0:
                timestamp = pvalue
            if pwire != 2:
                body += buf[pstart:pend]
            elif pfield == FTRACE_EVENTS:
                # Kept even when empty: the bundle's packet may carry sequence state.
                body += length_delimited(FTRACE_EVENTS, filter_bundle(buf, pvalue, sections))
            elif pfield == PROCESS_TREE:
                body += length_delimited(PROCESS_TREE, filter_tree(buf, pvalue, app_pids, thread_names))
            elif pfield == PROCESS_STATS:
                body += length_delimited(PROCESS_STATS, filter_stats(buf, pvalue, app_pids, rss, lambda: timestamp))
            elif pfield == FRAME_TIMELINE:
                drop_packet = True
            else:
                body += buf[pstart:pend]
        if not drop_packet:
            out += length_delimited(PACKET, bytes(body))
    sections.finish()
    return bytes(out), rss


def filter_bundle(buf, span, sections):
    body = bytearray()
    for field, wire, value, start, end in fields(buf, *span):
        if field == BUNDLE_COMPACT_SCHED:
            continue
        if field != BUNDLE_EVENT or wire != 2:
            body += buf[start:end]
            continue
        event = submessage(buf, value)
        if EVENT_PRINT not in event:
            continue
        marker = ""
        for pfield, pwire, pvalue, _, _ in fields(buf, *event[EVENT_PRINT][0]):
            if pfield == PRINT_BUF and pwire == 2:
                marker = text(buf, pvalue)
        tid = int32(event[EVENT_PID][0]) if EVENT_PID in event else -1
        ts = event[EVENT_TIMESTAMP][0] if EVENT_TIMESTAMP in event else 0
        if sections.keep(tid, ts, marker):
            body += buf[start:end]
    return bytes(body)


def filter_tree(buf, span, app_pids, thread_names):
    body = bytearray()
    for field, wire, value, start, end in fields(buf, *span):
        if wire != 2 or field not in (TREE_PROCESS, TREE_THREAD):
            body += buf[start:end]
            continue
        message = submessage(buf, value)
        if field == TREE_PROCESS:
            if message.get(PROCESS_PID) and int32(message[PROCESS_PID][0]) in app_pids:
                body += buf[start:end]
            continue
        tgid = int32(message[THREAD_TGID][0]) if THREAD_TGID in message else None
        if tgid not in app_pids:
            continue
        tid = int32(message[THREAD_TID][0]) if THREAD_TID in message else None
        payload = bytes(buf[value[0]:value[1]])
        has_name = any(text(buf, s) for s in message.get(THREAD_NAME, []))
        if not has_name and tid in thread_names:
            # A later occurrence of a singular field wins, so appending names it.
            payload += length_delimited(THREAD_NAME, thread_names[tid].encode())
        body += length_delimited(TREE_THREAD, payload)
    return bytes(body)


def filter_stats(buf, span, app_pids, rss, timestamp):
    body = bytearray()
    for field, wire, value, start, end in fields(buf, *span):
        if field != STATS_PROCESS or wire != 2:
            body += buf[start:end]
            continue
        message = submessage(buf, value)
        pid = int32(message[STATS_PID][0]) if STATS_PID in message else None
        if pid in app_pids:
            body += buf[start:end]
            if STATS_VM_RSS_KB in message:
                rss.append((timestamp(), pid, message[STATS_VM_RSS_KB][0]))
    return bytes(body)


# --- report ---------------------------------------------------------------------

def milliseconds(ns):
    return f"{ns / 1e6:.2f} ms"


def megabytes(kb):
    return f"{kb / 1024:.1f} MB"


def report(sections, thread_names, rss, prefixes, out):
    rows = sorted(sections.durations.items(), key=lambda item: -sum(item[1]))
    print(f"Sections starting with {', '.join(repr(p) for p in prefixes)} — wall time, begin to end", file=out)
    if not rows:
        print("  none — was the app used while recording? (signposts need a logged-in session)", file=out)
    else:
        width = max(len(name) for name, _ in rows)
        print(f"  {'name':<{width}}  {'count':>5}  {'total':>11}  {'median':>10}  {'max':>10}  threads", file=out)
        for name, durations in rows:
            threads = ", ".join(
                f"{thread_names.get(tid, tid)}×{n}" for tid, n in sections.threads[name].most_common(3))
            print(f"  {name:<{width}}  {len(durations):>5}  {milliseconds(sum(durations)):>11}  "
                  f"{milliseconds(statistics.median(durations)):>10}  {milliseconds(max(durations)):>10}  {threads}",
                  file=out)
    for name, count in sections.unclosed.items():
        print(f"  {name}: {count} never ended (still open when the trace stopped, or ended on another thread)",
              file=out)
    if rss:
        values = [kb for _, _, kb in rss]
        print(f"App RSS: {megabytes(values[0])} at start, {megabytes(max(values))} peak, "
              f"{megabytes(values[-1])} at end", file=out)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("trace", help="a Perfetto trace (.pftrace)")
    parser.add_argument("app_id", help="the app's process name, e.g. com.example.id1234.android")
    parser.add_argument("-o", "--output", help="write the focused trace here")
    parser.add_argument("--prefix", action="append",
                        help=f"keep sections starting with this; repeatable (default: {DEFAULT_PREFIXES})")
    parser.add_argument("--all-sections", action="store_true", help="keep every section of the app")
    args = parser.parse_args()

    prefixes = [""] if args.all_sections else (args.prefix or DEFAULT_PREFIXES)
    buf = open(args.trace, "rb").read()

    app_pids, thread_names = survey(buf, args.app_id)
    if not app_pids:
        sys.exit(f"error: no process named {args.app_id} in {args.trace} — was the app running?")

    sections = Sections(app_pids, prefixes)
    focused, rss = rewrite(buf, app_pids, thread_names, sections)
    if args.output:
        with open(args.output, "wb") as f:
            f.write(focused)
    report(sections, thread_names, rss, prefixes, sys.stdout)


if __name__ == "__main__":
    main()
