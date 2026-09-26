#!/bin/bash
#
# Fail unless the installed `skip` CLI is the version Package.swift pins.
#
# Usage: Scripts/Android/check-skip-version.sh [--install]
#
#   --install   for CI: on a mismatch or no skip at all, download the pinned
#               release from GitHub instead of failing and export it to later
#               GitHub Actions steps (GITHUB_PATH, and SKIP_COMMAND_OVERRIDE for
#               Gradle). Locally it changes nothing past this script's own PATH.
#
# The manifests pin skip with `exact:`, and a CLI that has drifted past that pin
# fails the build inside a dependency, far from the cause (`AndroidUserDefaults`
# … "must use a 'required' initializer"). CI installs skip through this, with
# --install (Scripts/Android/ci-setup.sh), so a Skip release cannot turn every
# push red. See Android/docs/build-and-run.md § CI.

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

INSTALL=0
case "${1:-}" in
    "")             ;;
    --install)      INSTALL=1 ;;
    -h|--help)      sed -n '3,16p' "$0" | cut -c3-; exit 0 ;;
    *)              die "unknown argument: $1" ;;
esac

PINNED="$(sed -nE 's@.*skiptools/skip\.git", exact: "([0-9.]+)".*@\1@p' "$ROOT/Package.swift" | head -1)"
[[ -n "$PINNED" ]] || die "no exact skip pin in Package.swift"
FAKIT_PINNED="$(sed -nE 's@.*skiptools/skip\.git", exact: "([0-9.]+)".*@\1@p' "$ROOT/FAKit/Package.swift" | head -1)"
[[ "$FAKIT_PINNED" == "$PINNED" ]] \
    || die "FAKit/Package.swift pins skip $FAKIT_PINNED but Package.swift pins $PINNED"

installed_version() {
    command -v skip >/dev/null || return 0
    skip version 2>/dev/null | sed -nE 's/^Skip version ([0-9.]+).*/\1/p' | head -1 || true
}
INSTALLED="$(installed_version)"
(( INSTALL )) || [[ -n "$INSTALLED" ]] || die "no usable \`skip\` on PATH"

if [[ "$INSTALLED" != "$PINNED" ]] && (( INSTALL )); then
    # What the Homebrew cask installs: a universal binary behind a wrapper script.
    DEST="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/skip-$PINNED"
    echo "skip ${INSTALLED:-(none)} is installed; fetching $PINNED into $DEST"
    rm -rf "$DEST" && mkdir -p "$DEST"
    curl -fsSL -o "$DEST/skip.zip" \
        "https://github.com/skiptools/skip/releases/download/$PINNED/skip-macos.zip"
    unzip -q "$DEST/skip.zip" -d "$DEST"
    BIN="$DEST/skip.artifactbundle/bin"
    [[ -x "$BIN/skip" ]] || die "the skip $PINNED download has no bin/skip"
    export PATH="$BIN:$PATH"
    if [[ -n "$GITHUB_PATH" ]]; then
        echo "$BIN" >> "$GITHUB_PATH"
        echo "SKIP_COMMAND_OVERRIDE=$BIN/skip" >> "$GITHUB_ENV"
    fi
    INSTALLED="$(installed_version)"
fi

[[ "$INSTALLED" == "$PINNED" ]] || die "skip $INSTALLED is installed but the manifests pin $PINNED.
    Upgrade the pin with everything it moves (Android/docs/build-and-run.md § Run)
    or install skip $PINNED."
echo "skip $INSTALLED, as pinned"
