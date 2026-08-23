#!/bin/bash
#
# Serialise access to the one shared Android emulator.
#
# Every worktree gets its own debug app (see Android/app/build.gradle.kts), but
# they all install onto the same ~2 GB AVD, and two of them building or testing
# at once fight over it while doubling the Gradle daemon's heap. This runs one
# command at a time. The lock records the holder's pid, so one left behind by a
# crashed run clears itself instead of deadlocking the next.
#
# Usage: Scripts/Android/with-emulator-lock.sh [--timeout SECONDS] <command…>
#
#   --timeout   how long to wait for the lock, default 1800s
#
# Exits with the wrapped command's status. Wrap anything that drives the
# emulator from a second worktree — `skip android test`, `skip app launch`, a
# bare `./gradlew` — but not Scripts/Android/run.sh, which takes the
# lock itself.
#
# Environment: FA_EMULATOR_LOCK (the lock file, default /tmp/fa-emulator.lock).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

LOCK="${FA_EMULATOR_LOCK:-/tmp/fa-emulator.lock}"
TIMEOUT=1800

while (( $# )); do
    case "$1" in
        -h|--help)    sed -n '3,20p' "$0" | cut -c3-; exit 0 ;;
        --timeout)    TIMEOUT="$2"; shift ;;
        --timeout=*)  TIMEOUT="${1#*=}" ;;
        --)           shift; break ;;
        *)            break ;;
    esac
    shift
done

[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "--timeout takes a number of seconds"
(( $# )) || die "nothing to run (see --help)"

# --- take the lock ----------------------------------------------------------

# shlock's link(2) dance is atomic, and it clears a lock whose pid is gone.
SHLOCK=/usr/bin/shlock
[[ -x "$SHLOCK" ]] || die "$SHLOCK is missing"

deadline=$(( SECONDS + TIMEOUT ))
announced=0

until "$SHLOCK" -f "$LOCK" -p $$; do
    (( SECONDS < deadline )) || die "the emulator lock ($LOCK) was still held after ${TIMEOUT}s"

    # Only worth saying once, and only if this is a real wait rather than two
    # commands brushing past each other.
    if (( announced == 0 && SECONDS >= 5 )); then
        holder="$(head -1 "$LOCK" 2>/dev/null | tr -dc '0-9')"
        if [[ -n "$holder" ]]; then
            echo "waiting for the emulator lock — held by pid $holder: $(ps -o command= -p "$holder" 2>/dev/null)" >&2
        else
            echo "waiting for the emulator lock ($LOCK)" >&2
        fi
        announced=1
    fi

    sleep 1
done

trap 'rm -f "$LOCK"' EXIT

# --- run --------------------------------------------------------------------

status=0
"$@" || status=$?
exit $status
