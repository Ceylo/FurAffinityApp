#!/bin/bash
#
# Mirror a worktree's sources into an Android build slot, rewriting only the files
# whose content changed: llbuild recompiles on an inode or mtime change alone.
#
# Usage: Scripts/Android/slot-sync.sh <worktree> <slot>
#        Scripts/Android/slot-sync.sh --list <worktree>
#            prints the file list, NUL-separated, and copies nothing
#
# The file list is git's (tracked plus untracked-not-ignored) plus the generated,
# git-ignored asset catalog entries skipstone needs, minus signing material and
# editor scratch files.
# <slot>/.slot-manifest records it, and a file that leaves the list is removed from
# the slot. Nothing else in the slot is touched — above all not its .build.
#
# macOS's rsync is openrsync, which ignored --delete and dir-merge filters and wiped
# a slot's .build; hence the manifest, and no deleting option here.
#
# The caller holds the slot's lease. Prints one summary line; exits non-zero on any
# failure, with rsync's own status if the copy fails. A listed file that vanishes
# mid-copy is dropped and the copy retried, three attempts in all; if files still
# vanish on the last one, the sync fails.

set -euo pipefail
export LC_ALL=C   # one byte order for sort and [[ < ]]

die() { echo "error: $*" >&2; exit 1; }

list_only=0
case "${1:-}" in
    -h|--help) sed -n '3,22p' "$0" | cut -c3-; exit 0 ;;
    --list)    list_only=1; shift ;;
esac
(( $# == 2 - list_only )) || { echo "usage: $0 <worktree> <slot> | --list <worktree>" >&2; exit 2; }

worktree="$(git -C "$1" rev-parse --show-toplevel)" || die "not a git worktree: $1"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/slot-sync.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Paths the sync may write or remove. Keeps it off the slot's own state, and drops
# nested repositories, which git lists as `dir/`.
owned() {
    case "$1" in
        ''|/*|*/|.build|.build/*|.lock|.slot-*|../*|*/../*|*/..) return 1 ;;
    esac
}

# Signing material is never copied, tracked or not (nothing tracked matches).
# shellcheck source=Scripts/signing-material.sh
source "$(dirname "${BASH_SOURCE[0]}")/../signing-material.sh"

# Editor swap, lock and backup files, which come and go mid-sync.
editor_scratch() {
    case "${1##*/}" in
        *.swp|.#*|*~) return 0 ;;
    esac
    return 1
}

# --- the new list -----------------------------------------------------------

{
    git -C "$worktree" ls-files -z -co --exclude-standard
    git -C "$worktree" ls-files -z -oi --exclude-standard -- FurAffinity/Resources/Assets.xcassets
} | while IFS= read -r -d '' path; do
    if ! owned "$path" || is_signing_material "$path" || editor_scratch "$path"; then continue; fi
    # -c also lists tracked files deleted from the working tree.
    [[ -e "$worktree/$path" || -L "$worktree/$path" ]] || continue
    printf '%s\0' "$path"
done | sort -zu > "$tmp/new"

if (( list_only )); then
    cat "$tmp/new"
    exit 0
fi

# Resolve the slot through its nearest existing ancestor, to check it before creating it.
dir="${2%/}" rest=""
while [[ ! -d "$dir" ]]; do
    rest="/${dir##*/}$rest"
    dir="$(dirname -- "$dir")"
done
slot="$(cd "$dir" && pwd -P)$rest"
case "$slot/" in
    "$worktree"/*) die "the slot $slot is inside the worktree $worktree" ;;
esac
mkdir -p "$slot"
manifest="$slot/.slot-manifest"

# --- removals: in the old manifest, not in the new list ---------------------

# Both lists are sorted, so one merge walk finds them.
changed=1
if cmp -s "$tmp/new" "$manifest"; then changed=0; fi
: > "$tmp/removed"
if (( changed )) && [[ -f "$manifest" ]]; then
    exec 3< "$tmp/new"
    have=0; IFS= read -r -d '' next <&3 && have=1
    while IFS= read -r -d '' old; do
        while (( have )) && [[ "$next" < "$old" ]]; do
            IFS= read -r -d '' next <&3 || have=0
        done
        (( have )) && [[ "$next" == "$old" ]] && continue
        if owned "$old"; then printf '%s\0' "$old"; fi
    done < "$manifest" > "$tmp/removed"
    exec 3<&-
fi

removed=0
while IFS= read -r -d '' path; do
    rm -f -- "$slot/$path"
    removed=$((removed + 1))
    # Drop the directories this emptied; rmdir refuses a non-empty one.
    dir="$(dirname -- "$path")"
    while [[ "$dir" != "." ]] && rmdir -- "$slot/$dir" 2>/dev/null; do
        dir="$(dirname -- "$dir")"
    done
done < "$tmp/removed"

# Written before the copy, so a copy that fails halfway leaves every file it
# may have created on the list for the next run to own.
if (( changed )); then
    cp "$tmp/new" "$manifest.tmp"
    mv -f "$manifest.tmp" "$manifest"
fi

# --- copy -------------------------------------------------------------------

# A listed file deleted since (an editor's): rsync exits 24, openrsync 23 with only
# stat errors naming it.
vanished_only() {
    local line path
    [[ -s "$tmp/errors" ]] || return 1
    while IFS= read -r line; do
        [[ "$line" =~ ^rsync\([0-9]+\):\ error:\ (.*):\ stat:\ No\ such\ file\ or\ directory$ ]] || return 1
        path="${BASH_REMATCH[1]}"
        [[ ! -e "$worktree/$path" && ! -L "$worktree/$path" ]] || return 1
    done < "$tmp/errors"
}

# --checksum --no-times: an identical file keeps its inode and mtime.
list="$tmp/new"
: > "$tmp/itemized"
for attempt in 1 2 3; do
    status=0
    /usr/bin/rsync -rlp --checksum --no-times --itemize-changes --from0 --files-from="$list" \
        "$worktree/" "$slot/" >> "$tmp/itemized" 2> "$tmp/errors" || status=$?
    if (( status != 23 || attempt == 3 )) || ! vanished_only; then break; fi
    # openrsync then also skips files in directories it had yet to create: copy
    # again, without what vanished.
    cat "$tmp/errors" >&2
    while IFS= read -r -d '' path; do
        if [[ -e "$worktree/$path" || -L "$worktree/$path" ]]; then printf '%s\0' "$path"; fi
    done < "$list" > "$tmp/retry$attempt"
    list="$tmp/retry$attempt"
done
cat "$tmp/errors" >&2
if (( status && status != 24 )); then
    cat "$tmp/itemized" >&2
    echo "error: rsync failed with status $status" >&2
    exit "$status"
fi

# Count files and links; `cd` lines are directories.
copied="$(grep -c '^[>c][fL]' "$tmp/itemized" || true)"
total="$(tr -cd '\0' < "$tmp/new" | wc -c | tr -d ' ')"
echo "slot-sync: $slot: $copied copied, $removed removed, $total files"
