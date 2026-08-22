#!/bin/bash
#
# Manage this worktree's own iOS simulator device.
#
# Every git worktree targets a device named after its directory — `FA android`,
# `FA ipados`, … — so two branches can be run side by side without one install
# overwriting the other's app container. The device is created on first use and
# reused afterwards; a shut-down one costs only disk.
#
# Usage: Scripts/iOS/simulator.sh [--udid|--shutdown] [device-type]
#
#   --udid       print the UDID and exit, creating the device if needed, e.g.
#                xcodebuild test -scheme FurAffinity \
#                    -destination "id=$(Scripts/iOS/simulator.sh --udid)"
#   --shutdown   shut the device down instead of booting it
#
# The device type defaults to $FA_SIM_DEVICE_TYPE, or `iPhone 17`; the runtime
# to $FA_SIM_RUNTIME, or `iOS 26.5`. Both take a simctl name or identifier, and
# only matter the first time — afterwards the existing device is reused as is.

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME="FA $(basename "$ROOT")"

MODE=boot
DEVICE_TYPE="${FA_SIM_DEVICE_TYPE:-iPhone 17}"
RUNTIME="${FA_SIM_RUNTIME:-iOS 26.5}"

while (( $# )); do
    case "$1" in
        -h|--help)   sed -n '3,19p' "$0" | cut -c3-; exit 0 ;;
        --udid)      MODE=udid ;;
        --shutdown)  MODE=shutdown ;;
        -*)          die "unknown option $1 (see --help)" ;;
        *)           DEVICE_TYPE="$1" ;;
    esac
    shift
done

# --- find or create the device ----------------------------------------------

# `simctl list` has no exact-name lookup, so match the "<name> (<udid>) (<state>)"
# line. Requiring the "(" right after the name is what keeps `FA android` from
# also matching `FA android-nested-observable`.
NAME_RE="$(printf '%s' "$NAME" | sed 's@[][\.*^$/]@\\&@g')"

device_udid() {
    xcrun simctl list devices available \
        | sed -nE "s@^[[:space:]]*$NAME_RE \(([0-9A-Fa-f-]{36})\) .*@\1@p" \
        | head -1
}

UDID="$(device_udid)"

if [[ -z "$UDID" ]]; then
    UDID="$(xcrun simctl create "$NAME" "$DEVICE_TYPE" "$RUNTIME")" \
        || die "could not create '$NAME' — see \`xcrun simctl list devicetypes runtimes\`"
    echo "created $NAME — $DEVICE_TYPE, $RUNTIME ($UDID)" >&2
fi

# --- act on it --------------------------------------------------------------

case "$MODE" in
    udid)
        echo "$UDID"
        ;;
    shutdown)
        # Already shut down is not a failure worth reporting.
        xcrun simctl shutdown "$UDID" 2>/dev/null || true
        echo "✓ $NAME is shut down"
        ;;
    boot)
        xcrun simctl bootstatus "$UDID" -b
        echo "✓ $NAME is booted ($UDID)"
        ;;
esac
