#!/bin/bash
#
# Install this repo's git hooks into the common .git directory, so they apply to
# every worktree of this clone. Idempotent: re-running just rewrites hooks this
# script itself installed (marked below); it refuses to touch a hook it didn't
# write.
#
# Usage: Scripts/install-git-hooks.sh
#
# Currently installs one hook:
#
#   post-checkout   seeds a brand-new worktree's DerivedData/SourcePackages from
#                   a sibling's (Scripts/iOS/seed-source-packages.sh), so it
#                   skips SwiftPM's package resolution and ~29 checkouts. Runs
#                   only for a new worktree or clone (previous HEAD is the null
#                   ref) and only if that worktree carries an executable
#                   seed-source-packages.sh. Never fails the checkout.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

MARKER="# Installed by Scripts/install-git-hooks.sh"
HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$HOOKS_DIR"

install_hook() {
  local name="$1" body="$2"
  local dst="$HOOKS_DIR/$name"
  if [ -e "$dst" ] && ! grep -qF "$MARKER" "$dst"; then
    die "$dst already exists and wasn't installed by this script; not overwriting it"
  fi
  printf '#!/bin/bash\n%s\n\n%s\n' "$MARKER" "$body" > "$dst"
  chmod +x "$dst"
  echo "install-git-hooks: installed $dst"
}

install_hook post-checkout '
prev_head="$1"
if [ "$prev_head" = "0000000000000000000000000000000000000000" ] \
    && [ -x Scripts/iOS/seed-source-packages.sh ]; then
  Scripts/iOS/seed-source-packages.sh || true
fi'
