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
# ANDROID_HOME / ANDROID_SDK_ROOT (SDK location), EMULATOR_BOOT_TIMEOUT (300s).

set -eo pipefail

TIMEOUT="${EMULATOR_BOOT_TIMEOUT:-300}"

die() { echo "error: $*" >&2; exit 1; }

case "${1:-}" in
    -h|--help) sed -n '3,14p' "$0" | cut -c3-; exit 0 ;;
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
    echo "booting $AVD (log: $LOG)"
    # Ignoring HUP/INT survives across exec, so the emulator outlives this
    # script being interrupted — a plain background child would die with it.
    ( trap '' HUP INT; exec "$EMULATOR" -avd "$AVD" ${1+"$@"} >"$LOG" 2>&1 ) &
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
