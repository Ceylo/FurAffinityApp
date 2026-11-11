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
# Exports ANDROID_SERIAL, ANDROID_TARGET_ABI (the device's ABI, empty without
# one) and, for the PC, FA_EMULATOR_LOCK, so the PC and this host each have
# their own lock.
#
# Expects $ADB.

select_android_target() {
    [[ -z "$FA_EMULATOR_LOCK_HELD" ]] || return 0

    local mode="$1" here="" reason serial
    local remote
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
        # Without a local device, a serial that fails the device check rather
        # than letting adb pick the PC.
        here="$("$ADB" devices 2>/dev/null | awk -v r="$serial" 'NR > 1 && $2 == "device" && $1 != r {print $1; exit}')"
        export ANDROID_SERIAL="${here:-emulator-5554}"
    fi

    export ANDROID_TARGET_ABI
    ANDROID_TARGET_ABI="$("$ADB" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r' || true)"
    if [[ "$mode" == remote ]]; then
        echo "Android device: $FA_REMOTE_EMULATOR_HOST ($ANDROID_TARGET_ABI)" >&2
    else
        echo "Android device: this host${ANDROID_TARGET_ABI:+ ($ANDROID_TARGET_ABI)}" >&2
    fi
}
