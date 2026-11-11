#!/bin/bash
#
# Bring the remote PC's emulator up as a device of this Mac's own adb server.
#
# The PC (an ssh alias in $FA_REMOTE_EMULATOR_HOST) runs an x86_64 emulator; an
# ssh tunnel carries its adbd port to 127.0.0.1:15555 here, and `adb connect`
# makes it a TCP device of the local server. Forwards, LLDB and Gradle then treat
# it as local, selected by ANDROID_SERIAL. See Android/docs/remote-emulator.md.
#
# Usage: Scripts/Android/remote-emulator.sh up|down|serial
#
#   up      exit 0 once the device is booted and connected, else non-zero with
#           a one-line reason on stderr. Wakes the PC first when it is asleep
#           and FA_REMOTE_EMULATOR_WAKE_MAC is set, and starts the emulator
#           through the PC's FAEmulator task when it isn't running
#   down    stop the PC's emulator, disconnect it and close the tunnel
#   serial  print the device's serial
#
# Environment: FA_REMOTE_EMULATOR_HOST, FA_REMOTE_EMULATOR_WAKE_MAC (the PC's
# MAC address, for a magic packet), ANDROID_HOME / ANDROID_SDK_ROOT.

set -eo pipefail

die() { echo "$*" >&2; exit 1; }

HOST="$FA_REMOTE_EMULATOR_HOST"
PORT=15555
SERIAL="127.0.0.1:$PORT"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
SOCK="/tmp/fa-remote-adb-$HOST.sock"
# The PC's adb, for the console commands that only listen on its own loopback.
PC_ADB='"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"'

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR)
pc() { ssh "${SSH_OPTS[@]}" "$HOST" "$@" 2>/dev/null; }

booted() {
    [[ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]
}

tunnel() {
    local i
    for (( i = 0; i < 3; i++ )); do
        ssh "${SSH_OPTS[@]}" -S "$SOCK" -O check "$HOST" 2>/dev/null && return 0
        ssh "${SSH_OPTS[@]}" -f -N -M -S "$SOCK" -o ControlPersist=30m \
            -o ExitOnForwardFailure=yes -L "$PORT:127.0.0.1:5555" "$HOST" 2>/dev/null && return 0
        sleep 1
    done
    return 1
}

connect() {
    "$ADB" connect "$SERIAL" >/dev/null 2>&1 || return 1
    [[ "$("$ADB" -s "$SERIAL" get-state 2>/dev/null | tr -d '\r')" == device ]]
}

wake() {
    [[ -n "$FA_REMOTE_EMULATOR_WAKE_MAC" ]] || return 1
    python3 - "$FA_REMOTE_EMULATOR_WAKE_MAC" <<'EOF'
import socket, sys
mac = bytes.fromhex(sys.argv[1].replace(":", "").replace("-", ""))
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
s.sendto(b"\xff" * 6 + mac * 16, ("255.255.255.255", 9))
EOF
    local deadline=$(( SECONDS + 60 ))
    until pc exit; do
        (( SECONDS < deadline )) || return 1
        sleep 2
    done
}

up() {
    [[ -n "$HOST" ]] || die "FA_REMOTE_EMULATOR_HOST is not set"
    [[ -x "$ADB" ]] || die "$ADB is missing"
    if ! pc exit; then
        wake || die "$HOST is unreachable"
    fi
    tunnel || die "no ssh tunnel to $HOST"
    connect && booted && return 0

    if ! connect; then
        pc schtasks /run /tn FAEmulator >/dev/null || die "could not start FAEmulator on $HOST"
    fi
    local deadline=$(( SECONDS + 180 ))
    until connect && booted; do
        (( SECONDS < deadline )) || die "the emulator on $HOST did not boot"
        sleep 3
    done
}

down() {
    [[ -n "$HOST" ]] || die "FA_REMOTE_EMULATOR_HOST is not set"
    pc "$PC_ADB" emu kill >/dev/null || true
    "$ADB" disconnect "$SERIAL" >/dev/null 2>&1 || true
    ssh "${SSH_OPTS[@]}" -S "$SOCK" -O exit "$HOST" 2>/dev/null || true
}

case "$1" in
    up)      up ;;
    down)    down ;;
    serial)  echo "$SERIAL" ;;
    *)       sed -n '3,20p' "$0" | cut -c3-; exit 2 ;;
esac
