#!/bin/bash
#
# Assert that each module carrying process-global state is defined by exactly
# one shared object in the APK payload.
#
# Usage: Scripts/Android/check-shared-globals.sh [debug|release]
#
# A SwiftPM *product* that is dynamic links its own package's target
# dependencies statically into itself. So while FALogging was a target inside
# FAKit, libFAKit.so and libFAPages.so each absorbed a private copy of it — of
# `FALogSubsystem.override`, and of `PersistentLogStore.shared`. Three stores
# then wrote `files/Logs/app.log` at three independent offsets and destroyed
# each other's lines, and the Kotlin bridge's `override` reached only one of
# the three. FALogging is its own package now, so FAKit and FAPages reach it as
# a cross-package product, which is linked dynamically. See
# Android/docs/shared-sources.md § One module, one image.
#
# Nothing at runtime can detect a relapse: an `assert` inside the app module
# compares two reads that both bind to *its* copy and passes either way. Only
# the symbol tables tell the truth, hence this check.
#
# The modules below are the ones that own mutable process-global state and are
# consumed by more than one image. Add a module here when it grows some.
# Kingfisher is here for `KingfisherManager.shared`, `ImageCache.default`,
# `ImageDownloader.default` and `NetworkMonitor.default`: two copies would give the
# app two image caches, and a downloader registered on one would be invisible to the
# other. Its fork's manifest makes the library `.dynamic` under SKIP_BRIDGE for that
# reason.
#
# Environment: ANDROID_HOME / ANDROID_SDK_ROOT (for the NDK's llvm-readelf).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Swift mangles a symbol's module as <length><name>, e.g. `$s9FALogging…`, and a
# static stored property as `…vpZ`. Both halves matter: the module prefix alone also
# matches symbols another module emits for a *retroactive extension* on this one — the
# app's `KingfisherManager.retrieveFAImage` is mangled under Kingfisher — and those are
# code, not state.
MODULES=(FALogging Kingfisher)

VARIANT="debug"
case "$1" in
    -h|--help)      sed -n '3,24p' "$0" | cut -c3-; exit 0 ;;
    "")             ;;
    debug|release)  VARIANT="$1" ;;
    *)              die "unknown variant: $1 (expected debug or release)" ;;
esac

# --- locate llvm-readelf ----------------------------------------------------

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
NDK="$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)"
[[ -n "$NDK" ]] || die "no NDK in $SDK/ndk — install one with \`skip android sdk install\`"

# A symlink in the toolchain, so no -type f here.
READELF="$(ls "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-readelf 2>/dev/null | head -1)"
[[ -n "$READELF" ]] || die "no llvm-readelf under $NDK"

# --- the payload ------------------------------------------------------------

LIBS="$ROOT/.build/Android/app/intermediates/merged_native_libs/$VARIANT"
LIBS="$(ls -d "$LIBS"/*/out/lib/arm64-v8a 2>/dev/null | head -1)"
[[ -n "$LIBS" ]] || die "no merged $VARIANT native libs — build the app first"

# --- one definer per module -------------------------------------------------

status=0

for module in "${MODULES[@]}"; do
    prefix="\$s${#module}$module"
    definers=()

    for so in "$LIBS"/*.so; do
        n=$("$READELF" --dyn-syms "$so" 2>/dev/null \
            | awk -v p="$prefix" '$4 == "OBJECT" && $7 != "UND" && index($8, p) == 1 && $8 ~ /vpZ$/' \
            | wc -l | tr -d ' ')
        (( n > 0 )) && definers+=("$(basename "$so"):$n")
    done

    case "${#definers[@]}" in
        1) echo "$module: one image — ${definers[0]%%:*}" ;;
        0) echo "warning: $module defines no globals in $VARIANT — is it still linked?" >&2 ;;
        *)
            status=1
            echo "error: $module is defined by ${#definers[@]} images, each with its own copy of" >&2
            echo "       every global. They will not see each other's writes:" >&2
            printf '         %s\n' "${definers[@]}" >&2
            first="${definers[0]%%:*}"
            "$READELF" --dyn-syms "$LIBS/$first" 2>/dev/null \
                | awk -v p="$prefix" '$4 == "OBJECT" && $7 != "UND" && index($8, p) == 1 && $8 ~ /vpZ$/ {print "         " $8}' >&2
            echo "       Make $module a cross-package product — see" >&2
            echo "       Android/docs/shared-sources.md § One module, one image." >&2
            ;;
    esac
done

exit $status
