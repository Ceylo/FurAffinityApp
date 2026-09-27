#!/bin/bash
#
# Seed a worktree's DerivedData/SourcePackages from a sibling worktree's, so a
# fresh worktree skips SwiftPM's package resolution and checkout entirely.
#
# Half of a fresh iOS build is package resolution, not compiling: SourcePackages
# is ~3.6 GB per worktree, 3.0 GB of it sentry-cocoa's 7 binary xcframework
# variants, unzipped from ~/Library/Caches/org.swift.swiftpm/artifacts into every
# worktree that resolves it, plus ~29 git working copies checked out from the
# shared bare repositories. None of that differs between worktrees pinned to the
# same Package.resolved, so it is copied wholesale (an APFS clone, so it costs no
# disk) instead of re-resolved. Only two kinds of absolute path need rewriting
# afterwards: the DerivedData directory SourcePackages sits under (in
# workspace-state.json's artifact paths, and in each checkout's .git config/
# alternates, which point at the sibling's SourcePackages/repositories), and the
# worktree path itself (in workspace-state.json's entry for the local FALogging
# package, referenced by path: rather than a git URL).
#
# Usage: Scripts/iOS/seed-source-packages.sh [worktree]
#
#   worktree   defaults to this script's own worktree
#
# Idempotent and quiet on success. Exits 0 (and prints one line) if no sibling
# qualifies, leaving normal package resolution to run. Never overwrites an
# existing SourcePackages.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE="$(cd "$HERE/../.." && pwd)"
WORKTREE="${1:-$WORKTREE}"
WORKTREE="$(cd "$WORKTREE" && pwd)"

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
RESOLVED="FurAffinity.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

[ -f "$WORKTREE/$RESOLVED" ] || die "$WORKTREE/$RESOLVED not found"

# Same algorithm Xcode uses for a DerivedData directory's name: md5 of the
# .xcodeproj's absolute path, each 8-byte half written as 14 base-26 letters.
# Verified against every existing FurAffinity-* directory (2026-09-27).
dd_hash() {
  python3 -c "
import hashlib, sys
h = hashlib.md5(sys.argv[1].encode()).digest()
def enc(half):
    n = int.from_bytes(half, 'big')
    letters = []
    for _ in range(14):
        n, r = divmod(n, 26)
        letters.append(chr(ord('a') + r))
    return ''.join(reversed(letters))
print(enc(h[:8]) + enc(h[8:]))
" "$1"
}

DST_HASH="$(dd_hash "$WORKTREE/FurAffinity.xcodeproj")"
DST="$DERIVED_DATA/FurAffinity-$DST_HASH"

if [ -d "$DST/SourcePackages" ]; then
  exit 0
fi

# Pick the most recently used sibling worktree pinned to the same
# Package.resolved (byte-identical, not just present) that still exists and has
# a fully resolved SourcePackages of its own.
SRC=""
SRC_MTIME=0
for info in "$DERIVED_DATA"/FurAffinity-*/info.plist; do
  [ -f "$info" ] || continue
  dd_dir="$(dirname "$info")"
  [ "$dd_dir" = "$DST" ] && continue
  ws_path="$(plutil -extract WorkspacePath raw -o - "$info" 2>/dev/null || true)"
  [ -n "$ws_path" ] || continue
  src_worktree="$(dirname "$ws_path")"
  [ -d "$src_worktree" ] || continue
  [ -f "$dd_dir/SourcePackages/workspace-state.json" ] || continue
  cmp -s "$src_worktree/$RESOLVED" "$WORKTREE/$RESOLVED" || continue
  mtime="$(stat -f %m "$info")"
  if [ "$mtime" -gt "$SRC_MTIME" ]; then
    SRC="$dd_dir"
    SRC_MTIME="$mtime"
    SRC_WORKTREE="$src_worktree"
  fi
done

if [ -z "$SRC" ]; then
  echo "seed-source-packages: no sibling worktree has a matching, resolved SourcePackages; resolving normally"
  exit 0
fi

mkdir -p "$DST"
cp -Rc "$SRC/SourcePackages" "$DST/SourcePackages"

for f in "$DST/SourcePackages/workspace-state.json" \
         "$DST/SourcePackages"/checkouts/*/.git/config \
         "$DST/SourcePackages"/checkouts/*/.git/objects/info/alternates; do
  [ -f "$f" ] || continue
  sed -i '' \
    -e "s#$SRC#$DST#g" \
    -e "s#$SRC_WORKTREE#$WORKTREE#g" \
    "$f"
done

if grep -rIl "$SRC" "$DST/SourcePackages/workspace-state.json" \
       "$DST/SourcePackages"/checkouts/*/.git/config \
       "$DST/SourcePackages"/checkouts/*/.git/objects/info/alternates 2>/dev/null | grep -q .; then
  rm -rf "$DST/SourcePackages"
  die "stale path from $SRC survived rewriting; removed the seeded copy"
fi

echo "seed-source-packages: seeded $DST/SourcePackages from $SRC"
