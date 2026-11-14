#!/bin/bash
#
# Print the path of the skip CLI at the version Package.swift pins, fetching it once.
#
# Usage: Scripts/Android/skip-cli.sh
#
# Each version lives in ~/Library/Caches/FurAffinity/skip/<version>/ (FA_SKIP_CACHE
# overrides the parent), downloaded from the same release zip SwiftPM's binaryTarget
# names and checked against that target's checksum. Branches pinning different
# versions thus coexist, and Homebrew's skip is never used. Scripts/Android/skip runs it.

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

skip_pin() { sed -nE 's@.*skiptools/skip\.git", exact: "([0-9.]+)".*@\1@p' "$1" | head -1; }
VERSION="$(skip_pin "$ROOT/Package.swift")"
[[ -n "$VERSION" ]] || die "no exact skip pin in Package.swift"
FAKIT_VERSION="$(skip_pin "$ROOT/FAKit/Package.swift")"
[[ "$FAKIT_VERSION" == "$VERSION" ]] \
    || die "FAKit/Package.swift pins skip $FAKIT_VERSION but Package.swift pins $VERSION"

CACHE="${FA_SKIP_CACHE:-$HOME/Library/Caches/FurAffinity/skip}"
DEST="$CACHE/$VERSION"
# Not bin/skip: that wrapper clears the binary's xattrs on every run, which the
# skipstone plugin's sandbox forbids, so this clears them once, here.
BIN="$DEST/skip.artifactbundle/macos/skip"

if [[ ! -x "$BIN" ]]; then
    echo "skip-cli: fetching skip $VERSION into $DEST" >&2
    mkdir -p "$CACHE"
    TMP="$(mktemp -d "$CACHE/.fetch-$VERSION.XXXXXX")"
    trap 'rm -rf "$TMP"' EXIT
    TAG="https://raw.githubusercontent.com/skiptools/skip/$VERSION/Package.swift"
    LINE="$(curl -fsSL "$TAG" | grep -E 'binaryTarget\(name: "skip".*skip-macos\.zip' | head -1)" \
        || die "could not read skip's manifest at $VERSION"
    URL="$(sed -nE 's/.*url: "([^"]+)".*/\1/p' <<<"$LINE")"
    SUM="$(sed -nE 's/.*checksum: "([0-9a-f]{64})".*/\1/p' <<<"$LINE")"
    [[ -n "$URL" && -n "$SUM" ]] || die "no macOS binaryTarget in skip's manifest at $VERSION"
    curl -fsSL -o "$TMP/skip.zip" "$URL"
    ACTUAL="$(shasum -a 256 "$TMP/skip.zip" | cut -d' ' -f1)"
    [[ "$ACTUAL" == "$SUM" ]] || die "skip $VERSION: checksum $ACTUAL, manifest says $SUM"
    unzip -q "$TMP/skip.zip" -d "$TMP/out"
    [[ -x "$TMP/out/skip.artifactbundle/macos/skip" ]] || die "the skip $VERSION zip has no macos/skip"
    xattr -cr "$TMP/out"
    [[ -e "$DEST" ]] || mv "$TMP/out" "$DEST" 2>/dev/null || true
    [[ -x "$BIN" ]] || die "could not install into $DEST"
fi

echo "$BIN"
