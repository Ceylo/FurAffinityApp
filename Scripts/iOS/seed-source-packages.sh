#!/bin/bash
#
# Seed a worktree's DerivedData/SourcePackages from a sibling worktree's, so a
# fresh worktree skips SwiftPM's package resolution and checkout entirely.
#
# Half of a fresh iOS build is package resolution: ~3.6 GB of unzipped binary
# artifacts and ~29 git checkouts, none of which differ between worktrees pinned
# to the same Package.resolved. So it is APFS-cloned (no disk cost), then the
# sibling's DerivedData and worktree paths are rewritten to this one's.
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
WORKTREE="$(cd "${1:-$HERE/../..}" && pwd)"

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

DST="$DERIVED_DATA/FurAffinity-$(dd_hash "$WORKTREE/FurAffinity.xcodeproj")"

if [ -d "$DST/SourcePackages" ]; then
  exit 0
fi

# Whether workspace-state.json $1 checked out every pin of Package.resolved $2.
# What the sibling resolved, not its Package.resolved: SwiftPM keeps a stale
# checkout's pins over a changed Package.resolved, and we'd copy them along.
resolved_to_pins() {
  python3 -c "
import json, sys
state = json.load(open(sys.argv[1]))['object']['dependencies']
have = {d['packageRef']['identity']: d['state'].get('checkoutState', {}).get('revision') for d in state}
pins = json.load(open(sys.argv[2]))['pins']
sys.exit(any(have.get(p['identity']) != p['state'].get('revision') for p in pins))
" "$1" "$2"
}

# Pick the most recently used sibling worktree whose SourcePackages is resolved
# to exactly this worktree's pins.
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
  mtime="$(stat -f %m "$info")"
  [ "$mtime" -gt "$SRC_MTIME" ] || continue
  resolved_to_pins "$dd_dir/SourcePackages/workspace-state.json" "$WORKTREE/$RESOLVED" || continue
  SRC="$dd_dir"
  SRC_MTIME="$mtime"
  SRC_WORKTREE="$src_worktree"
done

if [ -z "$SRC" ]; then
  echo "seed-source-packages: no sibling worktree has a matching, resolved SourcePackages; resolving normally"
  exit 0
fi

# Built aside and swapped in with one rename, so a Ctrl-C or a full disk during
# the multi-GB copy leaves no half-seeded SourcePackages at the path the exit
# check above trusts.
STAGING="$DST/SourcePackages.seeding.$$"
trap 'rm -rf "${STAGING:?}"' EXIT
mkdir -p "$DST"
cp -Rc "$SRC/SourcePackages" "$STAGING"

# Both paths only ever occur as a directory prefix. Anchoring on the "/" keeps a
# sibling named android from also matching android-x.
for f in "$STAGING/workspace-state.json" \
         "$STAGING"/checkouts/*/.git/config \
         "$STAGING"/checkouts/*/.git/objects/info/alternates; do
  [ -f "$f" ] || continue
  sed -i '' -e "s#$SRC/#$DST/#g" -e "s#$SRC_WORKTREE/#$WORKTREE/#g" "$f"
done

# rename(2), not mv: mv would nest it inside a SourcePackages that Xcode created
# meanwhile, and still report success.
if ! python3 -c 'import os, sys; os.rename(*sys.argv[1:])' "$STAGING" "$DST/SourcePackages" 2>/dev/null; then
  echo "seed-source-packages: Xcode created $DST/SourcePackages meanwhile; leaving it"
  exit 0
fi
echo "seed-source-packages: seeded $DST/SourcePackages from $SRC"
