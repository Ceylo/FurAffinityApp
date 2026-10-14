#!/usr/bin/env python3
"""The Android build slots (Android/build-slots), for clean.sh and cleanup-worktree.py.

Usage: slots.py delete-idle <pool>
           renames each idle slot into the trash. Records: trash, path, slot
           (empty for trash already there) and busy, slot, owner

It holds the pool lock throughout. Records are fields joined by \\x1f, which, unlike
a tab, `IFS=$'\\x1f' read` keeps apart when one is empty.
"""
import contextlib
import fcntl
import os
import re
import sys
import time


def emit(*fields):
    print("\x1f".join(str(f) for f in fields), flush=True)


def state(slot):
    """`.slot-state`: `key=value` lines, unescaped."""
    props = {}
    try:
        with open(os.path.join(slot, ".slot-state"), encoding="utf-8") as f:
            for line in f:
                key, sep, value = line.rstrip("\n").partition("=")
                if sep and key:
                    props[key] = value
    except OSError:
        pass
    return props


def lock(path, wait):
    """A POSIX lock, as Java's FileChannel takes (flock(1) doesn't see it); None if busy."""
    f = open(path, "a")
    try:
        fcntl.lockf(f, fcntl.LOCK_EX | (0 if wait else fcntl.LOCK_NB))
    except OSError:
        f.close()
        return None
    return f


@contextlib.contextmanager
def slots(pool):
    """(number, path) of each slot, under the pool lock."""
    held = lock(os.path.join(pool, ".android-slot-pool.lock"), wait=True)
    try:
        found = ((m, os.path.join(pool, n)) for n in os.listdir(pool)
                 if (m := re.fullmatch(r"android-slot-([1-9][0-9]*)", n)))
        yield sorted((int(m[1]), path) for m, path in found if os.path.isdir(path))
    finally:
        if held:
            held.close()


def describe(pool):
    """(path, idle|busy, owner, lastUsed) of each slot."""
    rows = []
    with slots(pool) as listed:
        for _, slot in listed:
            held = lock(os.path.join(slot, ".lock"), wait=False)
            if held:
                held.close()
            props = state(slot)
            rows.append((slot, "idle" if held else "busy", props.get("owner", ""), props.get("lastUsed", "0")))
    return rows


def delete_idle(pool):
    with slots(pool) as listed:
        for name in sorted(os.listdir(pool)):
            if name.startswith(".android-slot-trash-"):
                emit("trash", os.path.join(pool, name), "")
        for number, slot in listed:
            held = lock(os.path.join(slot, ".lock"), wait=False)
            if not held:
                emit("busy", slot, state(slot).get("owner", ""))
                continue
            trash = os.path.join(pool, f".android-slot-trash-{number}-{time.time_ns()}")
            os.rename(slot, trash)
            held.close()
            emit("trash", trash, slot)


def main(args):
    if len(args) >= 2 and args[0] == "delete-idle":
        delete_idle(args[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
