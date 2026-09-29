#!/usr/bin/env python3
"""The Android build slots (Android/build-slots), for clean.sh and cleanup-worktree.sh.

Usage: slots.py list <pool>
           a record per slot: slot, path, idle|busy, owner, lastUsed; then one per
           token, or registry entry (.android-slot-worktrees/<name>), whose worktree
           is not among the paths on stdin: token, path
       slots.py delete-idle <pool>
           renames each idle slot into the trash. Records: trash, path, slot
           (empty for trash already there) and busy, slot, owner
       slots.py drop-tokens [--dry-run] <pool> <token name>...
           deletes those tokens from every slot and the registry. Records:
           removed|would|failed, path

Each command holds the pool lock. Records are fields joined by \\x1f, which, unlike
a tab, `IFS=$'\\x1f' read` keeps apart when one is empty.
"""
import fcntl
import hashlib
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


def tokens(directory):
    """The `<sha1 of a worktree path>` files in a slot's .slot-tokens or the pool's registry."""
    names = sorted(os.listdir(directory)) if os.path.isdir(directory) else []
    return [os.path.join(directory, n) for n in names if re.fullmatch(r"[0-9a-f]{40}", n)]


def token_dirs(pool, listed):
    return [os.path.join(slot, ".slot-tokens") for _, slot in listed] + [os.path.join(pool, ".android-slot-worktrees")]


def list_slots(pool):
    live = {hashlib.sha1(p.encode()).hexdigest() for p in sys.stdin.read().splitlines()}
    listed = slots(pool)
    for _, slot in listed:
        held = lock(os.path.join(slot, ".lock"), wait=False)
        if held:
            held.close()
        props = state(slot)
        emit("slot", slot, "idle" if held else "busy", props.get("owner", ""), props.get("lastUsed", "0"))
    for directory in token_dirs(pool, listed):
        for token in tokens(directory):
            if os.path.basename(token) not in live:
                emit("token", token)


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


def drop_tokens(pool, names, dry_run):
    for directory in token_dirs(pool, slots(pool)):
        for name in dict.fromkeys(names):
            token = os.path.join(directory, name)
            if not os.path.isfile(token):
                continue
            if dry_run:
                emit("would", token)
                continue
            try:
                os.remove(token)
                emit("removed", token)
            except OSError:
                emit("failed", token)


def main(args):
    dry_run = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]
    if len(args) >= 2 and args[0] == "list":
        list_slots(args[1])
    elif len(args) >= 2 and args[0] == "delete-idle":
        delete_idle(args[1])
    elif len(args) >= 2 and args[0] == "drop-tokens":
        drop_tokens(args[1], args[2:], dry_run)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
