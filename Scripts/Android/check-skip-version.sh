#!/bin/bash
#
# Fail unless the installed `skip` CLI is the version Package.swift pins.
#
# Usage: Scripts/Android/check-skip-version.sh
#
# The manifests pin skip with `exact:`, and a CLI that has drifted past that pin
# fails the build inside a dependency, far from the cause (`AndroidUserDefaults`
# … "must use a 'required' initializer"). CI installs whatever Homebrew has, so
# its Android jobs run this first. See Android/docs/build-and-run.md § CI.

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

command -v skip >/dev/null || die "\`skip\` is not on PATH"

PINNED="$(sed -nE 's@.*skiptools/skip\.git", exact: "([0-9.]+)".*@\1@p' "$ROOT/Package.swift" | head -1)"
[[ -n "$PINNED" ]] || die "no exact skip pin in Package.swift"
FAKIT_PINNED="$(sed -nE 's@.*skiptools/skip\.git", exact: "([0-9.]+)".*@\1@p' "$ROOT/FAKit/Package.swift" | head -1)"
[[ "$FAKIT_PINNED" == "$PINNED" ]] \
    || die "FAKit/Package.swift pins skip $FAKIT_PINNED but Package.swift pins $PINNED"

INSTALLED="$(skip version 2>/dev/null | sed -nE 's/^Skip version ([0-9.]+).*/\1/p' | head -1)"
[[ -n "$INSTALLED" ]] || die "could not read \`skip version\`"

[[ "$INSTALLED" == "$PINNED" ]] || die "skip $INSTALLED is installed but the manifests pin $PINNED.
    Upgrade the pin with everything it moves (Android/docs/build-and-run.md § Run)
    or install skip $PINNED."
echo "skip $INSTALLED, as pinned"
