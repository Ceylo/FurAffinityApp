#!/bin/bash
#
# Build, install and start this worktree's debug app on the emulator.
#
# `skip app launch --android` reads the app id out of Skip.env, so it installs
# the per-worktree debug app fine and then fails to *start* it — the installed
# id carries a worktree suffix (see Android/app/build.gradle.kts). This does
# both against the right id, and holds the shared-emulator lock while it does.
#
# Usage: Scripts/Android/run.sh [--timeout SECONDS] [gradle args…]
#
#   --timeout   how long to wait for the emulator lock, default 1800s
#
# `./gradlew :app:installDebug` rather than `skip android build` is deliberate:
# it runs the whole pipeline, host bridge included, so it catches the class of
# `os(Android)`-guard error that `skip android build` never compiles.
#
# Boot an emulator first with Scripts/Android/start-emulator.sh — this
# does not start one. Environment: ANDROID_HOME / ANDROID_SDK_ROOT (SDK
# location), ANDROID_SERIAL (which device, when several are attached),
# JAVA_HOME (the JDK Gradle runs on).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

LOCK_ARGS=()

while (( $# )); do
    case "$1" in
        -h|--help)    sed -n '3,21p' "$0" | cut -c3-; exit 0 ;;
        --timeout)    LOCK_ARGS+=(--timeout "$2"); shift ;;
        --timeout=*)  LOCK_ARGS+=("$1") ;;
        --)           shift; break ;;
        *)            break ;;
    esac
    shift
done

# --- locate the SDK and the JDK ---------------------------------------------

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
[[ -x "$ADB" ]] || die "$ADB is missing — run \`skip android sdk install\`"
export ANDROID_HOME="$SDK"

# gradlew needs a JDK, and macOS ships only a `java` stub that errors out — so
# probe it rather than its existence. Android Studio's bundled runtime is the
# one Gradle syncs with anyway.
if [[ -z "$JAVA_HOME" ]] && ! java -version >/dev/null 2>&1; then
    JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    [[ -x "$JBR/bin/java" ]] || die "no JDK — set JAVA_HOME (Android Studio's is $JBR)"
    export JAVA_HOME="$JBR"
fi

# --- require a booted device ------------------------------------------------

[[ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" == device ]] \
    || die "no device — run Scripts/Android/start-emulator.sh (or set ANDROID_SERIAL)"

[[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] \
    || die "the device is still booting — Scripts/Android/start-emulator.sh waits for it"

# --- what to install and start ----------------------------------------------

# Value of a Skip.env key, ignoring the `//`-commented lines.
skip_env() {
    sed -nE "s@^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*@\1@p" "$ROOT/Skip.env" | head -1
}

# The distribution stash overrides the app id, so read it rather than assuming
# the placeholder com.example.id1234.
APP_ID="$(skip_env ANDROID_APPLICATION_ID)"
[[ -n "$APP_ID" ]] || APP_ID="$(skip_env PRODUCT_BUNDLE_IDENTIFIER)"
[[ -n "$APP_ID" ]] || die "no app id in $ROOT/Skip.env"

# Must match build.gradle.kts's sanitising of the same directory name.
WORKTREE="$(basename "$ROOT")"
APP_ID="$APP_ID.${WORKTREE//[^A-Za-z0-9_]/_}"

# Activities are named relatively in the manifest, so they resolve against the
# package name, not against the (suffixed) applicationId.
PKG="$(skip_env ANDROID_PACKAGE_NAME)"
[[ -n "$PKG" ]] || die "no ANDROID_PACKAGE_NAME in $ROOT/Skip.env"

# --- build, install, start --------------------------------------------------

# Everything above is a cheap check, so it runs before queueing for the lock and
# again on the far side of it; this is the part that must not overlap another
# worktree's.
if [[ -z "$FA_EMULATOR_LOCK_HELD" ]]; then
    export FA_EMULATOR_LOCK_HELD=1
    exec "$(dirname "${BASH_SOURCE[0]}")/with-emulator-lock.sh" "${LOCK_ARGS[@]}" \
        "${BASH_SOURCE[0]}" -- "$@"
fi

( cd "$ROOT/Android" && ./gradlew :app:installDebug "$@" )

echo "starting $APP_ID"
"$ADB" shell am start -n "$APP_ID/$PKG.MainActivity"
