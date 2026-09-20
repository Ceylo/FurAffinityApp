#!/bin/bash
#
# Install any given APK on the running emulator, keeping the app's data.
#
# `adb install -r -d`, never `adb uninstall`: a reinstall keeps the container,
# and wiping it costs the FA login *and* the Cloudflare clearance, which on the
# emulator can take a human tap to get back. `-d` is what lets an ordinary
# worktree build (versionCode 1) land over an android-distribution one (11900).
#
# Usage: Scripts/Android/install-apk.sh [--start] [--timeout SECONDS] <app.apk>
#
#   --start     launch the APK's launcher activity once it is installed
#   --timeout   how long to wait for the emulator lock, default 1800s
#
# Boot an emulator first with Scripts/Android/start-emulator.sh — this does not
# start one. To build *and* install this worktree's own app, use
# Scripts/Android/run.sh instead; this is for an APK you already have.
#
# Environment: ANDROID_HOME / ANDROID_SDK_ROOT (SDK location), ANDROID_SERIAL
# (which device, when several are attached).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

APK=""
START=0
LOCK_ARGS=()

while (( $# )); do
    case "$1" in
        -h|--help)    sed -n '3,21p' "$0" | cut -c3-; exit 0 ;;
        --start)      START=1 ;;
        --timeout)    LOCK_ARGS+=(--timeout "$2"); shift ;;
        --timeout=*)  LOCK_ARGS+=("$1") ;;
        --)           shift; break ;;
        -*)           die "unknown argument: $1" ;;
        *)            break ;;
    esac
    shift
done

(( $# <= 1 )) || die "one APK at a time"
APK="$1"

[[ -n "$APK" ]] || die "no APK given (see --help)"
[[ -f "$APK" ]] || die "no such file: $APK"
APK="$(cd "$(dirname "$APK")" && pwd)/$(basename "$APK")"

# --- locate the SDK ---------------------------------------------------------

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
[[ -x "$ADB" ]] || die "$ADB is missing — run \`skip android sdk install\`"

# Newest build-tools, for the badging dump that names the app id and activity.
AAPT2="$(ls -d "$SDK"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"

# --- require a booted device ------------------------------------------------

[[ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" == device ]] \
    || die "no device — run Scripts/Android/start-emulator.sh (or set ANDROID_SERIAL)"

[[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] \
    || die "the device is still booting — Scripts/Android/start-emulator.sh waits for it"

# --- what is in the APK -----------------------------------------------------

APP_ID=""
ACTIVITY=""
if [[ -n "$AAPT2" ]]; then
    badging="$("$AAPT2" dump badging "$APK" 2>/dev/null)" || die "not an APK: $APK"
    APP_ID="$(sed -nE "s/^package: name='([^']+)'.*/\1/p" <<< "$badging")"
    ACTIVITY="$(sed -nE "s/^launchable-activity: name='([^']+)'.*/\1/p" <<< "$badging" | head -1)"
    version="$(sed -nE "s/.*versionName='([^']*)'.*/\1/p" <<< "$badging" | head -1)"
elif (( START )); then
    die "--start needs aapt2 to read the app id — install Android SDK build-tools"
fi

# --- install ----------------------------------------------------------------

# Everything above is a cheap check, so it runs before queueing for the shared
# emulator lock and again on the far side of it; this is the part that must not
# overlap another worktree's.
if [[ -z "$FA_EMULATOR_LOCK_HELD" ]]; then
    export FA_EMULATOR_LOCK_HELD=1
    exec "$(dirname "${BASH_SOURCE[0]}")/with-emulator-lock.sh" "${LOCK_ARGS[@]}" \
        "${BASH_SOURCE[0]}" $([[ $START == 1 ]] && echo --start) -- "$APK"
fi

echo "installing ${APP_ID:-$APK}${version:+ $version}"

# A different signing key cannot be reinstalled over, and the way out — uninstall
# — is the one thing this script exists not to do behind the user's back.
if ! out="$("$ADB" install -r -d "$APK" 2>&1)"; then
    echo "$out" >&2
    if [[ "$out" == *UPDATE_INCOMPATIBLE* || "$out" == *signatures* ]]; then
        die "${APP_ID:-the app} is already installed with another signing key —" \
            "only an uninstall clears that, and it takes the FA login and the" \
            "Cloudflare clearance with it, so do it by hand if you mean to"
    fi
    die "install failed"
fi
echo "$out"

if (( START )); then
    [[ -n "$ACTIVITY" ]] || die "$APP_ID has no launcher activity to start"
    echo "starting $APP_ID"
    "$ADB" shell am start -n "$APP_ID/$ACTIVITY"
fi
