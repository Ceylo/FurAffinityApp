#!/usr/bin/env python3
"""The Android build slots (Android/build-slots), for clean.sh and cleanup-worktree.sh.

Usage: slots.py list <pool>
           a record per slot: slot, path, idle|busy, owner, lastUsed
       slots.py delete-idle <pool>
           renames each idle slot into the trash. Records: trash, path, slot
           (empty for trash already there) and busy, slot, owner

Each command holds the pool lock. Records are fields joined by \\x1f, which, unlike
a tab, `IFS=$'\\x1f' read` keeps apart when one is empty.
"""
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


def slots(pool):
    """(number, path) of each slot, taking the pool lock until exit."""
    global pool_lock
    pool_lock = lock(os.path.join(pool, ".android-slot-pool.lock"), wait=True)
    found = ((m, os.path.join(pool, n)) for n in os.listdir(pool)
             if (m := re.fullmatch(r"android-slot-([1-9][0-9]*)", n)))
    return sorted((int(m[1]), path) for m, path in found if os.path.isdir(path))


def list_slots(pool):
    for _, slot in slots(pool):
        held = lock(os.path.join(slot, ".lock"), wait=False)
        if held:
            held.close()
        props = state(slot)
        emit("slot", slot, "idle" if held else "busy", props.get("owner", ""), props.get("lastUsed", "0"))


def delete_idle(pool):
    listed = slots(pool)
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
    if len(args) >= 2 and args[0] == "list":
        list_slots(args[1])
    elif len(args) >= 2 and args[0] == "delete-idle":
        delete_idle(args[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
