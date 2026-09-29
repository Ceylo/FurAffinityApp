#!/bin/bash
#
# Delete this worktree's .build, so its next Android build is a clean one.
#
# The Skip/Swift side builds in a slot (Android/build-slots), and a build in any
# slot this worktree built in sees .build is gone and deletes that slot's .build
# too — so a plain `rm -rf .build` does the same thing. --all also deletes every
# idle slot and reports the busy ones.
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
        -h|--help)  sed -n '3,13p' "$0" | cut -c3-; exit 0 ;;
        --all)      ALL=1 ;;
        *)          die "unknown argument: $1 (see --help)" ;;
    esac
    shift
done

# Finder can drop a .DS_Store into a directory rm is emptying; a second pass gets
# it. A build may be removing the same trash: only what is left is an error.
remove() {
    rm -rf "$1" 2>/dev/null || rm -rf "$1" 2>/dev/null || true
    [[ ! -e "$1" && ! -L "$1" ]] || { echo "clean: could not delete $1" >&2; return 1; }
}

# The token first: once it is gone, the next build is clean even if the rest fails.
rm -f "$ROOT/.build/.fa-slot-token"
remove "$ROOT/.build"
echo "clean: deleted $ROOT/.build"

(( ALL )) || exit 0

SLOTS="${FA_ANDROID_SLOTS_DIR:-$HOME/Library/Developer/Xcode/DerivedData}"
[[ -d "$SLOTS" ]] || exit 0

# Each idle slot is renamed into the trash under its lock, then removed here.
records="$(/usr/bin/python3 "$ROOT/Scripts/Android/slots.py" delete-idle "$SLOTS")" \
    || die "could not lock the build slots in $SLOTS"

failed=0
while IFS=$'\x1f' read -r kind path detail; do
    case "$kind" in
        busy)  echo "clean: kept $path, busy with a build of ${detail:-unknown}" ;;
        trash) if [[ -n "$detail" ]]; then echo "clean: deleting $detail"; fi
               remove "$path" || failed=1 ;;
    esac
done <<< "$records"
exit "$failed"
