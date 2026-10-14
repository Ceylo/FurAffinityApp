#!/usr/bin/env python3
"""Cut a Perfetto trace down to one app's signposts, and summarise them.

A system trace holds every process on the device, and the app's own ATrace
sections are mostly the framework's and Compose's. This keeps only:

- the app's processes, their threads (named from the scheduler data, which the
  process tree lacks) and their memory counters;
- the app's sections whose name starts with one of the prefixes — by default
  our signposts, which OSCompat names `<category>: <name>`;
- two counter tracks computed from the scheduler data before it is dropped: how
  much CPU the app and its main thread used per 100 ms, in % of one core (so up
  to 400% on a 4-core emulator).

Everything else — scheduling, other processes, the frame timeline — is dropped,
so the output opens in https://ui.perfetto.dev as one process with a handful of
tracks. The full trace stays next to it for when the context matters.

    Scripts/Android/focus-trace.py fa.pftrace <app id> -o signposts.pftrace
    Scripts/Android/focus-trace.py fa.pftrace <app id> --prefix "Compose:" --prefix "FAKit: "

The summary (stdout) lists each signpost's count, total, median and max, and the
threads it ran on — durations are wall time from begin to end, not CPU time —
then the app's CPU and memory over the recording.

Only the fields read here are decoded, straight from the wire format, so this
needs no protobuf package. Field numbers are from Perfetto's
protos/perfetto/trace/perfetto_trace.proto.
"""

import argparse
import collections
import statistics
import struct
import sys

DEFAULT_PREFIXES = ["FAKit: ", "FAPages: "]
CPU_BUCKET_NS = 100_000_000
# Any id the recording's own sequences (small integers) do not use.
CPU_SEQUENCE_ID = 0x46414350

# TracePacket
PACKET = 1            # Trace.packet
FTRACE_EVENTS = 1     # TracePacket.ftrace_events
PROCESS_TREE = 2
PROCESS_STATS = 9
TIMESTAMP = 8
TRUSTED_SEQUENCE_ID = 10
TRACK_EVENT = 11
SEQUENCE_FLAGS = 13
TRACK_DESCRIPTOR = 60
FRAME_TIMELINE = 76
SEQ_INCREMENTAL_STATE_CLEARED = 1
# TrackDescriptor
DESCRIPTOR_UUID = 1
DESCRIPTOR_NAME = 2
DESCRIPTOR_PROCESS = 3
DESCRIPTOR_PARENT = 5
DESCRIPTOR_COUNTER = 8
PROCESS_DESCRIPTOR_PID = 1
COUNTER_UNIT_NAME = 6
# TrackEvent
TRACK_EVENT_TYPE = 9
TRACK_EVENT_TRACK = 11
TRACK_EVENT_DOUBLE_VALUE = 44
TYPE_COUNTER = 4
# FtraceEventBundle
BUNDLE_CPU = 1
BUNDLE_EVENT = 2
BUNDLE_COMPACT_SCHED = 4
# FtraceEvent
EVENT_TIMESTAMP = 1
EVENT_PID = 2         # the thread id
EVENT_PRINT = 3
PRINT_BUF = 2
# CompactSched
SCHED_INTERN_TABLE = 5
SCHED_SWITCH_TIMESTAMP = 1
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


def varint_field(field, value):
    return encode_varint(field << 3) + encode_varint(value)


def double_field(field, value):
    return encode_varint(field << 3 | 1) + struct.pack("<d", value)


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
    thread_tgids = {}
    for field, wire, packet, _, _ in fields(buf):
        if field != PACKET or wire != 2:
            continue
        for pfield, pwire, pvalue, _, _ in fields(buf, *packet):
            if pwire != 2:
                continue
            if pfield == PROCESS_TREE:
                for tfield, twire, tvalue, _, _ in fields(buf, *pvalue):
                    if tfield == TREE_THREAD and twire == 2:
                        thread = submessage(buf, tvalue)
                        if THREAD_TID in thread and THREAD_TGID in thread:
                            thread_tgids[int32(thread[THREAD_TID][0])] = int32(thread[THREAD_TGID][0])
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
    app_tids = {tid for tid, tgid in thread_tgids.items() if tgid in app_pids} | app_pids
    return app_pids, app_tids, thread_names


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


def cpu_usage(buf, app_tids, main_tids):
    """{bucket start ns: [app ns, main thread ns]}, replayed from sched_switch."""
    buckets = collections.defaultdict(lambda: [0, 0])
    running = {}   # cpu → (tid, since)

    def charge(tid, start, end):
        if tid not in app_tids:
            return
        is_main = tid in main_tids
        while start < end:
            bucket = start - start % CPU_BUCKET_NS
            chunk = min(end, bucket + CPU_BUCKET_NS) - start
            buckets[bucket][0] += chunk
            if is_main:
                buckets[bucket][1] += chunk
            start += chunk

    for field, wire, packet, _, _ in fields(buf):
        if field != PACKET or wire != 2:
            continue
        for pfield, pwire, pvalue, _, _ in fields(buf, *packet):
            if pfield != FTRACE_EVENTS or pwire != 2:
                continue
            bundle = submessage(buf, pvalue)
            if BUNDLE_COMPACT_SCHED not in bundle:
                continue
            cpu = bundle.get(BUNDLE_CPU, [0])[0]
            sched = submessage(buf, bundle[BUNDLE_COMPACT_SCHED][0])
            deltas = [v for s in sched.get(SCHED_SWITCH_TIMESTAMP, []) for v in packed_varints(buf, s)]
            next_tids = [int32(v) for s in sched.get(SCHED_SWITCH_NEXT_PID, []) for v in packed_varints(buf, s)]
            timestamp = 0
            for delta, tid in zip(deltas, next_tids):
                timestamp += delta   # the first is absolute
                if cpu in running:
                    previous, since = running[cpu]
                    charge(previous, since, timestamp)
                running[cpu] = (tid, timestamp)
    return dict(buckets)


def cpu_tracks(usage, app_pid):
    """Counter tracks for the app process: one packet per 100 ms bucket."""
    process_uuid, app_uuid, main_uuid = CPU_SEQUENCE_ID << 8 | 1, CPU_SEQUENCE_ID << 8 | 2, CPU_SEQUENCE_ID << 8 | 3
    out = bytearray()

    def packet(payload, first=False):
        body = payload + varint_field(TRUSTED_SEQUENCE_ID, CPU_SEQUENCE_ID)
        if first:
            body += varint_field(SEQUENCE_FLAGS, SEQ_INCREMENTAL_STATE_CLEARED)
        return length_delimited(PACKET, body)

    out += packet(length_delimited(TRACK_DESCRIPTOR,
                                   varint_field(DESCRIPTOR_UUID, process_uuid)
                                   + length_delimited(DESCRIPTOR_PROCESS,
                                                      varint_field(PROCESS_DESCRIPTOR_PID, app_pid))),
                  first=True)
    for uuid, name in ((app_uuid, "CPU: app"), (main_uuid, "CPU: main thread")):
        out += packet(length_delimited(TRACK_DESCRIPTOR,
                                       varint_field(DESCRIPTOR_UUID, uuid)
                                       + length_delimited(DESCRIPTOR_NAME, name.encode())
                                       + varint_field(DESCRIPTOR_PARENT, process_uuid)
                                       + length_delimited(DESCRIPTOR_COUNTER,
                                                          length_delimited(COUNTER_UNIT_NAME, b"% of a core"))))
    if not usage:
        return bytes(out)
    first, last = min(usage), max(usage)
    for bucket in range(first, last + CPU_BUCKET_NS, CPU_BUCKET_NS):
        app_ns, main_ns = usage.get(bucket, (0, 0))
        for uuid, ns in ((app_uuid, app_ns), (main_uuid, main_ns)):
            event = (varint_field(TRACK_EVENT_TYPE, TYPE_COUNTER)
                     + varint_field(TRACK_EVENT_TRACK, uuid)
                     + double_field(TRACK_EVENT_DOUBLE_VALUE, 100 * ns / CPU_BUCKET_NS))
            out += packet(varint_field(TIMESTAMP, bucket) + length_delimited(TRACK_EVENT, event))
    return bytes(out)


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
    rss = []   # KB, in recording order
    for field, wire, packet, raw_start, raw_end in fields(buf):
        if field != PACKET or wire != 2:
            out += buf[raw_start:raw_end]
            continue
        body = bytearray()
        drop_packet = False
        for pfield, pwire, pvalue, pstart, pend in fields(buf, *packet):
            if pwire != 2:
                body += buf[pstart:pend]
            elif pfield == FTRACE_EVENTS:
                # Kept even when empty: the bundle's packet may carry sequence state.
                body += length_delimited(FTRACE_EVENTS, filter_bundle(buf, pvalue, sections))
            elif pfield == PROCESS_TREE:
                body += length_delimited(PROCESS_TREE, filter_tree(buf, pvalue, app_pids, thread_names))
            elif pfield == PROCESS_STATS:
                body += length_delimited(PROCESS_STATS, filter_stats(buf, pvalue, app_pids, rss))
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


def filter_stats(buf, span, app_pids, rss):
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
                rss.append(message[STATS_VM_RSS_KB][0])
    return bytes(body)


# --- report ---------------------------------------------------------------------

def milliseconds(ns):
    return f"{ns / 1e6:.2f} ms"


def megabytes(kb):
    return f"{kb / 1024:.1f} MB"


def report(sections, thread_names, rss, usage, prefixes, out):
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
    if usage:
        start = min(usage)
        span = range(start, max(usage) + CPU_BUCKET_NS, CPU_BUCKET_NS)
        for slot, label in ((0, "App CPU"), (1, "Main thread CPU")):
            percents = [100 * usage.get(b, (0, 0))[slot] / CPU_BUCKET_NS for b in span]
            peak = max(range(len(percents)), key=percents.__getitem__)
            print(f"{label}: {statistics.mean(percents):.0f}% of a core on average, peak "
                  f"{percents[peak]:.0f}% at +{peak * CPU_BUCKET_NS / 1e9:.1f} s (per 100 ms)", file=out)
    if rss:
        print(f"App RSS: {megabytes(rss[0])} at start, {megabytes(max(rss))} peak, "
              f"{megabytes(rss[-1])} at end", file=out)


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

    app_pids, app_tids, thread_names = survey(buf, args.app_id)
    if not app_pids:
        sys.exit(f"error: no process named {args.app_id} in {args.trace} — was the app running?")

    usage = cpu_usage(buf, app_tids, app_pids)
    sections = Sections(app_pids, prefixes)
    focused, rss = rewrite(buf, app_pids, thread_names, sections)
    if args.output:
        with open(args.output, "wb") as f:
            f.write(focused)
            # A restarted app has several pids; its counters go under the last one.
            f.write(cpu_tracks(usage, max(app_pids)))
    report(sections, thread_names, rss, usage, prefixes, sys.stdout)


if __name__ == "__main__":
    main()
