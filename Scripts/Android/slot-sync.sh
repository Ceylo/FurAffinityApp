#!/bin/bash
#
# Mirror a worktree's sources into an Android build slot, rewriting only the files
# whose content changed: llbuild recompiles on an inode or mtime change alone.
#
# Usage: Scripts/Android/slot-sync.sh <worktree> <slot>
#
# The file list is git's (tracked plus untracked-not-ignored) plus the generated,
# git-ignored asset catalog entries skipstone needs, minus signing material.
# <slot>/.slot-manifest records it, and a file that leaves the list is removed from
# the slot. Nothing else in the slot is touched — above all not its .build.
#
# macOS's rsync is openrsync, which ignored --delete and dir-merge filters and wiped
# a slot's .build; hence the manifest, and no deleting option here.
#
# The caller holds the slot's lease. Prints one summary line; exits non-zero on any
# failure, with rsync's own status if the copy fails.

set -euo pipefail
export LC_ALL=C   # one byte order for sort and [[ < ]]

die() { echo "error: $*" >&2; exit 1; }

case "${1:-}" in
    -h|--help) sed -n '3,17p' "$0" | cut -c3-; exit 0 ;;
esac
(( $# == 2 )) || { echo "usage: $0 <worktree> <slot>" >&2; exit 2; }

worktree="$(git -C "$1" rev-parse --show-toplevel)" || die "not a git worktree: $1"

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
tmp="$(mktemp -d "${TMPDIR:-/tmp}/slot-sync.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Paths the sync may write or remove. Keeps it off the slot's own state, and drops
# nested repositories, which git lists as `dir/`.
owned() {
    case "$1" in
        ''|/*|*/|.build|.build/*|.lock|.slot-*|../*|*/../*|*/..) return 1 ;;
    esac
}

# Never copied, tracked or not (nothing tracked matches). The same list as
# signing_material() in Scripts/cleanup-worktree.sh.
signing() {
    case "${1##*/}" in
        *.p12|*.mobileprovision|*.jks|*.keystore|keystore.properties|.sentryclirc) return 0 ;;
    esac
    return 1
}

# --- the new list -----------------------------------------------------------

{
    git -C "$worktree" ls-files -z -co --exclude-standard
    git -C "$worktree" ls-files -z -oi --exclude-standard -- FurAffinity/Resources/Assets.xcassets
} | while IFS= read -r -d '' path; do
    if ! owned "$path" || signing "$path"; then continue; fi
    # -c also lists tracked files deleted from the working tree.
    [[ -e "$worktree/$path" || -L "$worktree/$path" ]] || continue
    printf '%s\0' "$path"
done | sort -zu > "$tmp/new"

# --- removals: in the old manifest, not in the new list ---------------------

# Both lists are sorted, so one merge walk finds them.
: > "$tmp/removed"
if [[ -f "$manifest" ]]; then
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
if ! cmp -s "$tmp/new" "$manifest"; then
    cp "$tmp/new" "$manifest.tmp"
    mv -f "$manifest.tmp" "$manifest"
fi

# --- copy -------------------------------------------------------------------

# --checksum --no-times: an identical file keeps its inode and mtime.
status=0
/usr/bin/rsync -rlp --checksum --no-times --itemize-changes --from0 --files-from="$tmp/new" \
    "$worktree/" "$slot/" > "$tmp/itemized" || status=$?
if (( status )); then
    cat "$tmp/itemized" >&2
    echo "error: rsync failed with status $status" >&2
    exit "$status"
fi

# Count files and links; `cd` lines are directories.
copied="$(grep -c '^[>c][fL]' "$tmp/itemized" || true)"
total="$(tr -cd '\0' < "$tmp/new" | wc -c | tr -d ' ')"
echo "slot-sync: $slot: $copied copied, $removed removed, $total files"
