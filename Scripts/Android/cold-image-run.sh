#!/bin/bash
#
# One cold image run: force-stop this worktree's app, wipe the coil disk cache,
# clear logcat, launch, wait for the burst to drain, dump the `FA` log.
#
# The cold burst *is* the measurement — do not scroll the feed during it. The
# whole 72-item Followed page is prefetched here, so a scroll afterwards serves
# every thumbnail from disk and moves nothing (Android/docs/images.md).
#
# Usage: Scripts/Android/cold-image-run.sh OUT.log [--wait SECONDS] [--timeout SECONDS]
#
#   --wait      how long to let the burst drain before dumping, default 50s
#   --timeout   how long to wait for the emulator lock, default 1800s
#
# Runs must never overlap — a background loop colliding with a manual launch
# has already produced one bogus measurement — so this holds the shared-emulator
# lock for its whole duration.
#
# It flags two things on the way out:
#   - a page-path Cloudflare challenge (`Cloudflare challenge on URLSession fetch`),
#     which is context, not automatically a discard;
#   - a feed page that never loaded, which is the one discard rule. That is read off
#     `prefetchThumbnails count=`, NOT off the image GET count: a run where the image
#     layer collapses issues very few GETs too, and discarding those would throw away
#     the worst outcome there is. One h2 arm produced four runs that loaded all 72
#     feed items and then lost every single image.
#
# Environment: ANDROID_HOME / ANDROID_SDK_ROOT, ANDROID_SERIAL, as run.sh.

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

OUT=""
WAIT=50
LOCK_ARGS=()

while (( $# )); do
    case "$1" in
        -h|--help)    sed -n '3,25p' "$0" | cut -c3-; exit 0 ;;
        --wait)       WAIT="$2"; shift ;;
        --wait=*)     WAIT="${1#*=}" ;;
        --timeout)    LOCK_ARGS+=(--timeout "$2"); shift ;;
        --timeout=*)  LOCK_ARGS+=("$1") ;;
        -*)           die "unknown option $1 (see --help)" ;;
        *)            [[ -z "$OUT" ]] || die "one output path, not two"; OUT="$1" ;;
    esac
    shift
done

[[ -n "$OUT" ]] || die "no output path (see --help)"
[[ "$WAIT" =~ ^[0-9]+$ ]] || die "--wait takes a number of seconds"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
[[ -x "$ADB" ]] || die "$ADB is missing — run \`skip android sdk install\`"

[[ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" == device ]] \
    || die "no device — run Scripts/Android/start-emulator.sh"

# --- which app -------------------------------------------------------------
#
# Same derivation as run.sh: the distribution stash overrides the app id,
# and every worktree carries its own suffix (Android/app/build.gradle.kts).

skip_env() {
    sed -nE "s@^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*@\1@p" "$ROOT/Skip.env" | head -1
}

APP_ID="$(skip_env ANDROID_APPLICATION_ID)"
[[ -n "$APP_ID" ]] || APP_ID="$(skip_env PRODUCT_BUNDLE_IDENTIFIER)"
[[ -n "$APP_ID" ]] || die "no app id in $ROOT/Skip.env"
WORKTREE="$(basename "$ROOT")"
APP_ID="$APP_ID.${WORKTREE//[^A-Za-z0-9_]/_}"

PKG="$(skip_env ANDROID_PACKAGE_NAME)"
[[ -n "$PKG" ]] || die "no ANDROID_PACKAGE_NAME in $ROOT/Skip.env"

# --- run -------------------------------------------------------------------

if [[ -z "$FA_EMULATOR_LOCK_HELD" ]]; then
    export FA_EMULATOR_LOCK_HELD=1
    exec "$(dirname "${BASH_SOURCE[0]}")/with-emulator-lock.sh" "${LOCK_ARGS[@]}" \
        "${BASH_SOURCE[0]}" "$OUT" --wait "$WAIT"
fi

"$ADB" shell am force-stop "$APP_ID"
# `run-as` is the only way into a debuggable app's private cache dir.
"$ADB" shell run-as "$APP_ID" rm -rf cache/fa_coil_cache
"$ADB" logcat -c
"$ADB" shell am start -n "$APP_ID/$PKG.MainActivity" >/dev/null
sleep "$WAIT"
"$ADB" logcat -d -s fur.affinity.ui/FA > "$OUT"

# --- verdict ---------------------------------------------------------------

gets=$(grep -c '\[Coil\] GET request on' "$OUT" || true)
loaded=$(sed -nE 's/.*prefetchThumbnails count=([0-9]+).*/\1/p' "$OUT" | head -1)
echo "=== $(basename "$OUT"): ${loaded:-0} feed items, $gets image GETs ==="

if grep -q 'Cloudflare challenge on URLSession fetch' "$OUT"; then
    echo "note: the page path was challenged this run — context, not a discard"
fi

if (( ${loaded:-0} < 20 )); then
    echo "DISCARD: the feed page never loaded, so there is no image burst to compare"
    exit 1
fi

if (( gets < loaded )); then
    echo "note: only $gets of $loaded items reached the network — if few of those"
    echo "      succeeded the image layer stalled, which is a result, not a discard"
fi
