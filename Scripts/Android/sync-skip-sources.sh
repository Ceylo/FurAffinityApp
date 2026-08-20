#!/bin/bash
#
# Maintains FurAffinityUI/Sources — the symlink farm that *is* the Android build's
# source list. skipstone walks the whole target directory and honors neither
# SwiftPM `sources:` nor `exclude:`, so the only way to keep iOS-only code out of
# the Android build is to keep it out of that directory.
#
# The two halves of the farm are maintained differently on purpose:
#
#   - FurAffinity/**/Android/*.swift is Android-only by construction, so every one
#     of those files is linked automatically. Adding one is just adding the file.
#   - a *shared* file is linked by hand (`ln -s`). That deliberate step is what
#     makes the farm the port allowlist: an unported plain-SwiftUI file stays in
#     the common base and out of the Android build until someone ports it.
#
# So this script prunes dangling links, adds the missing Android-only ones, and
# leaves shared links alone. It fails on a basename collision (the farm is flat)
# and on a link into an `iOS/` directory (iOS-only code leaking into Android).
#
# Usage:
#   Scripts/Android/sync-skip-sources.sh            # fix the farm
#   Scripts/Android/sync-skip-sources.sh --check    # report only, exit 1 if stale

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
farm="$root/FurAffinityUI/Sources"

check_only=0
case "${1-}" in
    --check) check_only=1 ;;
    "") ;;
    *) echo "usage: $(basename "$0") [--check]" >&2; exit 2 ;;
esac

mkdir -p "$farm"

status=0
report() {
    if (( check_only )); then
        echo "$1"
        status=1
    else
        echo "$1"
    fi
}
fail() { echo "error: $1" >&2; exit 1; }

# Absolute path a farm link points at. Reads the link *before* changing directory:
# once we cd to resolve the relative target, the link name no longer resolves.
resolve() {
    local target
    target="$(cd "$farm" && readlink "$1")"
    (cd "$farm/$(dirname "$target")" && printf '%s/%s\n' "$(pwd)" "$(basename "$target")")
}

# --- validate what is there -------------------------------------------------
for link in "$farm"/*; do
    [ -e "$link" ] || [ -L "$link" ] || continue
    name="$(basename "$link")"

    [ -L "$link" ] || fail "$name is a real file; the farm holds only symlinks"

    if [ ! -e "$link" ]; then
        report "prune dangling $name"
        (( check_only )) || rm "$link"
        continue
    fi

    case "$(resolve "$name")" in
        */iOS/*) fail "$name resolves into an iOS/ directory — iOS-only code must not reach the Android build" ;;
    esac
done

# --- add every Android-only source that has no link -------------------------
while IFS= read -r file; do
    name="$(basename "$file")"
    rel="${file#"$root"/}"
    link="$farm/$name"

    if [ -L "$link" ]; then
        existing="$(resolve "$name")"
        [ "$existing" = "$file" ] && continue
        fail "basename collision: $name is both $rel and ${existing#"$root"/}"
    fi

    report "link $name -> $rel"
    (( check_only )) || ln -s "../../$rel" "$link"
done < <(find "$root/FurAffinity" -type d -name Android -exec find {} -name '*.swift' -print \; | sort)

if (( check_only )) && (( status )); then
    echo "farm is out of date; run $(basename "$0") without --check" >&2
    exit 1
fi
