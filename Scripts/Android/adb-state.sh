# Sourced by the scripts that need a booted device; expects $ADB.
# shellcheck shell=bash

# Prints `adb get-state`'s answer, or its error. A freshly started adb server
# reports a running emulator `offline` for about half a second; only that
# state is waited out.
adb_state() {
    local state i
    for (( i = 0; i < 20; i++ )); do
        state="$("$ADB" get-state 2>&1 | tr -d '\r' | tail -n 1)"
        [[ "$state" == *offline* ]] || break
        sleep 0.25
    done
    echo "$state"
}
