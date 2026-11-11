#!/bin/bash
#
# Build, install and start this worktree's debug (or profile) app on the emulator.
#
# `skip app launch --android` reads the app id out of Skip.env, so it installs
# the per-worktree debug app fine and then fails to *start* it — the installed
# id carries a worktree suffix (see Android/app/build.gradle.kts). This does
# both against the right id, and holds the shared-emulator lock while it does.
#
# Usage: Scripts/Android/run.sh [--local|--remote] [--profile] [--timeout SECONDS]
#                               [gradle args…]
#
#   --local     this host's emulator; by default the remote PC's when it is
#               available (Scripts/Android/android-target.sh)
#   --remote    the remote PC's emulator, or fail
#   --profile   install the `profile` build type instead: release code, profileable,
#               under the debug app's id so it keeps its login. Record it with
#               Scripts/Android/profile.sh; see Android/docs/profiling.md.
#               On this host unless --remote: profile.sh never uses the PC
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

VARIANT=debug
TARGET=auto
LOCK_ARGS=()

while (( $# )); do
    case "$1" in
        -h|--help)    sed -n '3,31p' "$0" | cut -c3-; exit 0 ;;
        --profile)    VARIANT=profile ;;
        --local|--remote)  TARGET="${1#--}" ;;
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
# shellcheck source=Scripts/Android/adb-state.sh
source "$(dirname "${BASH_SOURCE[0]}")/adb-state.sh"
[[ -x "$ADB" ]] || die "$ADB is missing — run \`skip android sdk install\`"
export ANDROID_HOME="$SDK"

# shellcheck source=Scripts/Android/java-home.sh
source "$(dirname "${BASH_SOURCE[0]}")/java-home.sh"

# --- require a booted device ------------------------------------------------

# shellcheck source=Scripts/Android/android-target.sh
source "$(dirname "${BASH_SOURCE[0]}")/android-target.sh"
[[ $VARIANT == profile && $TARGET == auto ]] && TARGET=local
select_android_target "$TARGET"

[[ "$(adb_state)" == device ]] \
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
        "${BASH_SOURCE[0]}" $([[ $VARIANT == profile ]] && echo --profile) -- "$@"
fi

[[ -n "$ANDROID_TARGET_ARCH" ]] \
    || die "no Swift build for the device's ABI (${ANDROID_TARGET_ABI:-none: is $ANDROID_SERIAL connected?})"

TASK=":app:install$(tr '[:lower:]' '[:upper:]' <<< "${VARIANT:0:1}")${VARIANT:1}"
( cd "$ROOT/Android" && SKIP_EXPORT_ARCHS="$ANDROID_TARGET_ARCH" ./gradlew "$TASK" "$@" )

# Gradle prints its own errors and still says BUILD SUCCESSFUL, so this gate
# gets its own exit status: a relapse to one module per consumer is invisible
# at runtime (see the script's header).
ABI="$ANDROID_TARGET_ABI" "$(dirname "${BASH_SOURCE[0]}")/check-shared-globals.sh" "$VARIANT" \
    || die "shared globals are duplicated — the app above was installed anyway"

# Compile the Kotlin ahead of time, so a profile measures the app rather than ART's
# JIT warming up. On the emulator this takes ~8 minutes and can overrun dex2oat's
# 570 s limit, which leaves the install-time baseline-profile compile in place.
if [[ $VARIANT == profile ]]; then
    echo "compiling $APP_ID ahead of time (several minutes on the emulator)"
    result="$("$ADB" shell cmd package compile -m speed -f "$APP_ID" | tr -d '\r')"
    [[ "$result" == Success ]] || echo "warning: AOT compile failed ($result) — still on the" \
        "install-time filter, so Kotlin is partly JIT; rerun: adb shell cmd package compile -m speed -f $APP_ID" >&2
fi

echo "starting $APP_ID"
"$ADB" shell am start -n "$APP_ID/$PKG.MainActivity"
