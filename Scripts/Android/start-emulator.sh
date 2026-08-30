#!/bin/bash
#
# Boot an Android emulator and return only once it is actually usable.
#
# `skip app launch --android` reports the emulator as `offline` both when none
# is running and while one is still booting, so it needs a device that has
# already reached sys.boot_completed=1. This does that and nothing else — it
# never builds or launches the app.
#
# Usage: Scripts/Android/start-emulator.sh [avd-name] [extra emulator flags…]
#
# The AVD defaults to $ANDROID_AVD, or to the only installed one. Environment:
# ANDROID_HOME / ANDROID_SDK_ROOT (SDK location), EMULATOR_BOOT_TIMEOUT (300s),
# EMULATOR_MEMORY (guest RAM in MB, 3072).
#
# hw.ramSize in config.ini is ignored below 4096MB — the emulator silently raises
# it, and `-memory` alone does not override that. Only `-lowram` lifts the floor,
# and it leaves ro.config.low_ram unset, so the guest is a normal device with less
# RAM. Both flags are passed together; passing either yourself replaces ours.

set -eo pipefail

TIMEOUT="${EMULATOR_BOOT_TIMEOUT:-300}"
MEMORY="${EMULATOR_MEMORY:-3072}"

die() { echo "error: $*" >&2; exit 1; }

case "${1:-}" in
    -h|--help) sed -n '3,19p' "$0" | cut -c3-; exit 0 ;;
esac

# --- locate the SDK ---------------------------------------------------------

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
[[ -d "$SDK" ]] || die "no Android SDK at $SDK — set ANDROID_HOME or run \`skip android sdk install\`"

ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"
[[ -x "$ADB" ]] || die "$ADB is missing — run \`skip android sdk install\`"
[[ -x "$EMULATOR" ]] || die "$EMULATOR is missing — run \`skip android sdk install\`"

# Serial of the first emulator that is both online and done booting, if any.
booted_serial() {
    local serial state
    while read -r serial state _; do
        [[ "$serial" == emulator-* && "$state" == device ]] || continue
        [[ "$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] || continue
        echo "$serial"
        return 0
    done < <("$ADB" devices 2>/dev/null)
    return 1
}

if serial="$(booted_serial)"; then
    echo "✓ $serial is already booted"
    exit 0
fi

# --- pick the AVD -----------------------------------------------------------

if [[ -n "${1:-}" && "${1:-}" != -* ]]; then
    AVD="$1"
    shift
else
    AVD="${ANDROID_AVD:-}"
fi

if [[ -z "$AVD" ]]; then
    avds=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && avds+=("$line")
    done < <("$EMULATOR" -list-avds 2>/dev/null)

    case ${#avds[@]} in
        0) die "no AVDs installed — run \`skip android sdk install\`" ;;
        1) AVD="${avds[0]}" ;;
        *) die "several AVDs installed, name one: ${avds[*]}" ;;
    esac
fi

"$EMULATOR" -list-avds 2>/dev/null | grep -qx "$AVD" || die "unknown AVD '$AVD' (see \`$EMULATOR -list-avds\`)"

# --- boot it ----------------------------------------------------------------

LOG="/tmp/android-emulator-$AVD.log"
emu_pid=""

if "$ADB" devices 2>/dev/null | grep -q '^emulator-' || pgrep -qf "avd $AVD"; then
    echo "an emulator is already starting — waiting for it to finish booting"
else
    # Add each flag only if the caller did not pass their own.
    want_memory=1
    want_lowram=1
    for arg in ${1+"$@"}; do
        case "$arg" in
            -memory) want_memory=0 ;;
            -lowram) want_lowram=0 ;;
        esac
    done
    mem_args=()
    if (( want_memory )); then mem_args+=(-memory "$MEMORY"); fi
    if (( want_lowram )); then mem_args+=(-lowram); fi

    if (( want_memory )); then
        echo "booting $AVD with ${MEMORY}MB RAM (log: $LOG)"
    else
        echo "booting $AVD with the RAM size you passed (log: $LOG)"
    fi
    # Ignoring HUP/INT survives across exec, so the emulator outlives this
    # script being interrupted — a plain background child would die with it.
    ( trap '' HUP INT; exec "$EMULATOR" -avd "$AVD" "${mem_args[@]}" ${1+"$@"} >"$LOG" 2>&1 ) &
    emu_pid=$!
fi

# --- wait for boot ----------------------------------------------------------

deadline=$(( SECONDS + TIMEOUT ))
kicked=0

while true; do
    if [[ -n "$emu_pid" ]] && ! kill -0 "$emu_pid" 2>/dev/null; then
        echo "--- tail of $LOG ---" >&2
        tail -n 20 "$LOG" >&2
        die "the emulator exited before finishing boot"
    fi

    # We adopted someone else's emulator rather than starting one, so there is
    # no pid to watch. If it has since gone away — an `adb emu kill` racing this
    # script, or a shutdown still in progress when we looked — there is nothing
    # left to wait for, and waiting the full timeout only hides that.
    if [[ -z "$emu_pid" ]] && ! pgrep -qf "avd $AVD" \
        && ! "$ADB" devices 2>/dev/null | grep -q '^emulator-'; then
        die "the emulator we were waiting on is gone — rerun to boot a new one"
    fi

    if serial="$(booted_serial)"; then
        break
    fi

    (( SECONDS < deadline )) || die "$AVD did not boot within ${TIMEOUT}s — see $LOG"

    # A device stuck `offline` past the halfway mark means adb lost the
    # connection rather than a slow boot; restarting the server clears it.
    if (( kicked == 0 && SECONDS > deadline - TIMEOUT / 2 )) \
        && "$ADB" devices 2>/dev/null | grep -q 'offline'; then
        echo "device is offline — restarting the adb server"
        "$ADB" kill-server >/dev/null 2>&1 || true
        kicked=1
    fi

    sleep 2
done

echo "✓ $serial booted — \`skip app launch --android\` is ready"
