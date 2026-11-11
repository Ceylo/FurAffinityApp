# Sourced by the scripts that drive a device through adb; picks which one.
# shellcheck shell=bash
#
# select_android_target auto|local|remote
#
#   auto    the remote PC's emulator (Scripts/Android/remote-emulator.sh) when
#           FA_REMOTE_EMULATOR_HOST is set and it comes up, else this host's.
#           Unset, CI, or an ANDROID_SERIAL set by the caller mean this host
#   local   this host's emulator or device
#   remote  the PC's emulator, or fail
#
# Exports ANDROID_SERIAL, ANDROID_TARGET_MODE (local or remote),
# ANDROID_TARGET_ABI and ANDROID_TARGET_ARCH (the device's ABI, and its Swift
# name, empty when the tests and app don't build for it) and, for the PC,
# FA_EMULATOR_LOCK, so the PC and this host each have their own lock.

select_android_target() {
    [[ -z "$FA_EMULATOR_LOCK_HELD" ]] || return 0

    local mode="$1" here="" reason serial remote
    local adb="${ADB:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}/platform-tools/adb}"
    remote="$(dirname "${BASH_SOURCE[0]}")/remote-emulator.sh"
    serial="$("$remote" serial)"

    if [[ "$mode" == auto ]]; then
        if [[ -n "$CI" || -n "$ANDROID_SERIAL" || -z "$FA_REMOTE_EMULATOR_HOST" ]]; then
            mode=local
        elif reason="$("$remote" up 2>&1)"; then
            mode=remote
        else
            echo "remote emulator unavailable ($reason); using this host" >&2
            mode=local
        fi
    elif [[ "$mode" == remote ]]; then
        reason="$("$remote" up 2>&1)" || { echo "error: remote emulator: $reason" >&2; exit 1; }
    fi

    if [[ "$mode" == remote ]]; then
        export ANDROID_SERIAL="$serial"
        export FA_EMULATOR_LOCK=/tmp/fa-emulator-remote.lock
    elif [[ -z "$ANDROID_SERIAL" || "$ANDROID_SERIAL" == "$serial" ]]; then
        here="$("$adb" devices 2>/dev/null | awk -v r="$serial" 'NR > 1 && $2 == "device" && $1 != r {print $1; exit}')"
        [[ -n "$here" ]] || { echo "error: no device on this host — run Scripts/Android/start-emulator.sh" >&2; exit 1; }
        export ANDROID_SERIAL="$here"
    fi

    export ANDROID_TARGET_MODE="$mode" ANDROID_TARGET_ABI ANDROID_TARGET_ARCH
    ANDROID_TARGET_ABI="$("$adb" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r' || true)"
    case "$ANDROID_TARGET_ABI" in
        x86_64)     ANDROID_TARGET_ARCH=x86_64 ;;
        arm64-v8a)  ANDROID_TARGET_ARCH=aarch64 ;;
        *)          ANDROID_TARGET_ARCH= ;;
    esac
    if [[ "$mode" == remote ]]; then
        echo "Android device: $FA_REMOTE_EMULATOR_HOST ($ANDROID_TARGET_ABI)" >&2
    else
        echo "Android device: this host${ANDROID_TARGET_ABI:+ ($ANDROID_TARGET_ABI)}" >&2
    fi
}
