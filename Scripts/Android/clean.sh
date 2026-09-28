#!/bin/bash
#
# Delete this worktree's .build, so its next Android build is a clean one.
#
# The Skip/Swift side builds in a slot (Android/build-slots), and the next build
# sees .build is gone and deletes the slot's .build too — so a plain `rm -rf .build`
# does the same thing. --all also deletes every idle slot and reports the busy ones.
#
# Usage: Scripts/Android/clean.sh [--all]
#
# Environment: FA_ANDROID_SLOTS_DIR (the slots' parent, default
# ~/Library/Developer/Xcode/DerivedData).

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ALL=0

while (( $# )); do
    case "$1" in
        -h|--help)  sed -n '3,12p' "$0" | cut -c3-; exit 0 ;;
        --all)      ALL=1 ;;
        *)          die "unknown argument: $1 (see --help)" ;;
    esac
    shift
done

# Finder can drop a .DS_Store into a directory rm is emptying; a second pass gets it.
remove() { rm -rf "$1" 2>/dev/null || rm -rf "$1"; }

# The token first: once it is gone, the next build is clean even if the rest fails.
rm -f "$ROOT/.build/.fa-slot-token"
remove "$ROOT/.build"
echo "clean: deleted $ROOT/.build"

(( ALL )) || exit 0

SLOTS="${FA_ANDROID_SLOTS_DIR:-$HOME/Library/Developer/Xcode/DerivedData}"
[[ -d "$SLOTS" ]] || exit 0

# The plugin's locks are Java FileChannel locks, i.e. POSIX (fcntl) locks, which
# flock(1) doesn't see; Python's fcntl.lockf takes the same kind. The pool lock keeps
# a build from listing a slot this renames away. Each idle slot is renamed into the
# trash under its own lock, and the trash paths come out on stdout.
trash="$(/usr/bin/python3 - "$SLOTS" <<'PY'
import fcntl, os, re, sys, time

pool_dir = sys.argv[1]
pool = open(os.path.join(pool_dir, ".android-slot-pool.lock"), "a")
fcntl.lockf(pool, fcntl.LOCK_EX)

def owner(slot):
    try:
        with open(os.path.join(slot, ".slot-state")) as state:
            for line in state:
                if line.startswith("owner="):
                    return line[len("owner="):].strip()
    except OSError:
        pass
    return "unknown"

names = os.listdir(pool_dir)
print("\n".join(os.path.join(pool_dir, n) for n in names if n.startswith(".android-slot-trash-")))
slots = sorted(
    (int(m.group(1)), n) for n in names
    if (m := re.fullmatch(r"android-slot-([1-9][0-9]*)", n)) and os.path.isdir(os.path.join(pool_dir, n))
)
for number, name in slots:
    slot = os.path.join(pool_dir, name)
    lock = open(os.path.join(slot, ".lock"), "a")
    try:
        fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print(f"clean: kept {slot}, busy with a build of {owner(slot)}", file=sys.stderr)
        lock.close()
        continue
    trash = os.path.join(pool_dir, f".android-slot-trash-{number}-{time.time_ns()}")
    os.rename(slot, trash)
    lock.close()
    print(trash)
    print(f"clean: deleting {slot}", file=sys.stderr)
PY
)" || die "could not lock the build slots in $SLOTS"

while IFS= read -r path; do
    if [[ -n "$path" ]]; then remove "$path"; fi
done <<< "$trash"
