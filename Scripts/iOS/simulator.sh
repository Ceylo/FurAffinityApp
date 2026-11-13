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
# to $FA_SIM_RUNTIME, or iOS 27.2 — by identifier, since a beta runtime of the
# same name may be installed beside it. iOS 27 because Xcode's device-interaction
# tools (taps, swipes, typing) only drive simulators of its own SDK. The device
# type only matters the first time; a device on another runtime is replaced, which
# drops its app container (login included).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME="FA $(basename "$ROOT")"

MODE=boot
DEVICE_TYPE="${FA_SIM_DEVICE_TYPE:-iPhone 17}"
RUNTIME="${FA_SIM_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-27-2}"

while (( $# )); do
    case "$1" in
        -h|--help)   sed -n '3,22p' "$0" | cut -c3-; exit 0 ;;
        --udid)      MODE=udid ;;
        --shutdown)  MODE=shutdown ;;
        -*)          die "unknown option $1 (see --help)" ;;
        *)           DEVICE_TYPE="$1" ;;
    esac
    shift
done

# --- find or create the device ----------------------------------------------

command -v jq >/dev/null || die "jq is missing"

# `udid runtime` of the device named $NAME, if any.
device() {
    xcrun simctl list devices available -j \
        | jq -r --arg name "$NAME" \
            '[.devices | to_entries[] | .key as $rt | .value[] | select(.name == $name)
              | "\(.udid) \($rt)"][0] // empty'
}

# A runtime given by name (`iOS 27.2`) is resolved to its identifier to compare.
RUNTIME_ID="$(xcrun simctl list runtimes -j \
    | jq -r --arg rt "$RUNTIME" \
        '[.runtimes[] | select(.identifier == $rt or .name == $rt)][0].identifier // empty')"
[[ -n "$RUNTIME_ID" ]] || die "runtime '$RUNTIME' is not installed — see \`xcrun simctl list runtimes\`"

read -r UDID CURRENT_RUNTIME <<< "$(device)"

if [[ -n "$UDID" && "$CURRENT_RUNTIME" != "$RUNTIME_ID" ]]; then
    echo "replacing $NAME: it runs ${CURRENT_RUNTIME##*.}, not ${RUNTIME_ID##*.}" >&2
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    xcrun simctl delete "$UDID"
    UDID=""
fi

if [[ -z "$UDID" ]]; then
    UDID="$(xcrun simctl create "$NAME" "$DEVICE_TYPE" "$RUNTIME_ID")" \
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
