#!/bin/bash
#
# Prepare a native Swift debugging session for this worktree's debug app.
#
# Installs a build whose Swift .so still carry line tables, starts lldb-server
# inside the app sandbox, and writes .vscode/{settings,launch}.json pointing at
# both. Then attach from VS Code: Run ▸ Swift (Android), and the toolchain's
# Swift-aware LLDB breaks in Swift source.
#
# Usage: Scripts/Android/debug.sh [--no-build] [--restart] [--timeout SECONDS]
#
#   --no-build  skip the build and install, just (re)start lldb-server against
#               whatever is installed — only sound if that build had symbols
#   --restart   force-stop the app and start it again before attaching
#   --timeout   how long to wait for the emulator lock, default 1800s
#
# Kotlin is a separate debugger and this script does not touch it: Android
# Studio, Run ▸ Attach Debugger to Android Process, **Java/Kotlin only**. Both
# debuggers can sit on the process at once — JDWP and ptrace are different
# channels — but Studio's own native/dual mode takes the ptrace slot LLDB
# needs, so leave it on Java.
#
# Boot an emulator first with Scripts/Android/start-emulator.sh — this does not
# start one. Environment: ANDROID_HOME / ANDROID_SDK_ROOT (SDK location),
# ANDROID_SERIAL (which device, when several are attached), JAVA_HOME (the JDK
# Gradle runs on), TOOLCHAINS_DIR (where to look for the Swift toolchain).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BUILD=1
RESTART=0
LOCK_ARGS=()

while (( $# )); do
    case "$1" in
        -h|--help)    sed -n '3,26p' "$0" | cut -c3-; exit 0 ;;
        --no-build)   BUILD=0 ;;
        --restart)    RESTART=1 ;;
        --timeout)    LOCK_ARGS+=(--timeout "$2"); shift ;;
        --timeout=*)  LOCK_ARGS+=("$1") ;;
        --)           shift; break ;;
        *)            die "unknown argument: $1" ;;
    esac
    shift
done

# --- locate the SDK and the JDK ---------------------------------------------

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
[[ -x "$ADB" ]] || die "$ADB is missing — run \`skip android sdk install\`"
export ANDROID_HOME="$SDK"

# Same probe as run.sh: macOS ships a `java` stub that errors out, so test it
# rather than its existence.
if [[ -z "$JAVA_HOME" ]] && ! java -version >/dev/null 2>&1; then
    JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    [[ -x "$JBR/bin/java" ]] || die "no JDK — set JAVA_HOME (Android Studio's is $JBR)"
    export JAVA_HOME="$JBR"
fi

# --- require a booted device ------------------------------------------------

[[ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" == device ]] \
    || die "no device — run Scripts/Android/start-emulator.sh (or set ANDROID_SERIAL)"

[[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] \
    || die "the device is still booting — Scripts/Android/start-emulator.sh waits for it"

# LLDB's remote-android platform shells out to `adb` itself, and picks the
# device out of ANDROID_SERIAL. Pin it now so the generated launch.json names
# the same device this script set up, even if another one appears later.
SERIAL="${ANDROID_SERIAL:-$("$ADB" get-serialno | tr -d '\r')}"
export ANDROID_SERIAL="$SERIAL"

ABI="$("$ADB" shell getprop ro.product.cpu.abi | tr -d '\r')"

# --- what to debug ----------------------------------------------------------

# Value of a Skip.env key, ignoring the `//`-commented lines.
skip_env() {
    sed -nE "s@^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*@\1@p" "$ROOT/Skip.env" | head -1
}

APP_ID="$(skip_env ANDROID_APPLICATION_ID)"
[[ -n "$APP_ID" ]] || APP_ID="$(skip_env PRODUCT_BUNDLE_IDENTIFIER)"
[[ -n "$APP_ID" ]] || die "no app id in $ROOT/Skip.env"

WORKTREE="$(basename "$ROOT")"
APP_ID="$APP_ID.${WORKTREE//[^A-Za-z0-9_]/_}"

PKG="$(skip_env ANDROID_PACKAGE_NAME)"
[[ -n "$PKG" ]] || die "no ANDROID_PACKAGE_NAME in $ROOT/Skip.env"

# --- locate the two debugger halves -----------------------------------------

# Host side: lldb-dap from a swift.org toolchain. Xcode's LLDB knows Swift too
# but not the Android fixes that landed in Swift 6.3 (module-load deadlock,
# attach crashes, Android pointer tagging), and its Swift support targets Apple
# platforms — so require the open-source toolchain and say so when it's absent.
TC_DIR="${TOOLCHAINS_DIR:-$HOME/Library/Developer/Toolchains}"
LLDB_DAP=""
for tc in "$TC_DIR/swift-latest.xctoolchain" "$TC_DIR"/swift-*.xctoolchain \
          /Library/Developer/Toolchains/swift-latest.xctoolchain; do
    [[ -x "$tc/usr/bin/lldb-dap" ]] || continue
    LLDB_DAP="$tc/usr/bin/lldb-dap"
    break
done
[[ -n "$LLDB_DAP" ]] || die "no swift.org toolchain under $TC_DIR — install one from swift.org
       (Xcode's own LLDB is not enough: the Android fixes are in Swift 6.3+)"

# Device side: lldb-server from the NDK, matching the device's ABI. There is no
# Swift build of it — the Swift half all lives in the host's LLDB.
NDK="$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)"
[[ -n "$NDK" ]] || die "no NDK in $SDK/ndk — install one with \`skip android sdk install\`"

case "$ABI" in
    arm64-v8a)    SERVER_ARCH=aarch64 ;;
    armeabi-v7a)  SERVER_ARCH=arm ;;
    x86_64)       SERVER_ARCH=x86_64 ;;
    x86)          SERVER_ARCH=i386 ;;
    *)            die "no lldb-server mapping for ABI $ABI" ;;
esac

LLDB_SERVER="$(ls "$NDK"/toolchains/llvm/prebuilt/*/lib/clang/*/lib/linux/"$SERVER_ARCH"/lldb-server 2>/dev/null | sort -V | tail -1)"
[[ -n "$LLDB_SERVER" ]] || die "no $SERVER_ARCH lldb-server under $NDK"

# --- build and install ------------------------------------------------------

# Everything above is a cheap check, so it runs before queueing for the lock and
# again on the far side of it; this is the part that must not overlap another
# worktree's.
if [[ -z "$FA_EMULATOR_LOCK_HELD" ]]; then
    export FA_EMULATOR_LOCK_HELD=1
    args=()
    (( BUILD )) || args+=(--no-build)
    (( RESTART )) && args+=(--restart) || true
    exec "$(dirname "${BASH_SOURCE[0]}")/with-emulator-lock.sh" "${LOCK_ARGS[@]}" \
        "${BASH_SOURCE[0]}" "${args[@]}"
fi

if (( BUILD )); then
    # Two steps rather than a bare installDebug: lldb-server ignores the last
    # entry of an APK (llvm/llvm-project#173966), and ours is a .so — the last
    # thing `assembleDebug` writes is lib/<abi>/libSkipUI.so. Installing with
    # testOnly re-packs the APK so a manifest entry lands last instead, and the
    # payload stays reachable.
    ( cd "$ROOT/Android" && ./gradlew :app:assembleDebug -PfaDebugSymbols )
    ( cd "$ROOT/Android" && ./gradlew :app:installDebug -PfaDebugSymbols \
        -Pandroid.injected.testOnly=true )

    "$(dirname "${BASH_SOURCE[0]}")/check-shared-globals.sh" debug \
        || die "shared globals are duplicated — the app above was installed anyway"
fi

"$ADB" shell pm path "$APP_ID" >/dev/null 2>&1 \
    || die "$APP_ID is not installed — run without --no-build"

# --- lldb-server, inside the app sandbox ------------------------------------

# It has to run as the app's uid to ptrace it, which means living in the app's
# own data directory: `run-as` is the only way in on a non-rooted device.
SOCKET="$APP_ID/lldb.sock"

"$ADB" shell run-as "$APP_ID" pkill -f lldb-server >/dev/null 2>&1 || true

# 44 MB over adb twice per run adds up; the staged copy survives reboots, so
# only push when it is not already there at the right size.
STAGED=/data/local/tmp/lldb-server
want=$(stat -f%z "$LLDB_SERVER")
have=$("$ADB" shell "stat -c %s $STAGED 2>/dev/null" | tr -d '\r' || true)
if [[ "$want" != "$have" ]]; then
    echo "pushing lldb-server ($((want / 1024 / 1024)) MB)"
    "$ADB" push "$LLDB_SERVER" "$STAGED" >/dev/null
fi
# /data/local/tmp is drwxrwx--x, so an app uid can traverse into it but only
# reach a world-readable file.
"$ADB" shell chmod 644 "$STAGED"
"$ADB" shell run-as "$APP_ID" cp "$STAGED" ./lldb-server
"$ADB" shell run-as "$APP_ID" chmod 700 ./lldb-server

# Three slashes, not two: the abstract socket name is the URL's *path*, and with
# `unix-abstract://$SOCKET` the app id parses as the host instead — leaving the
# server listening on a name that the forward LLDB sets up never reaches.
#
# Detached on the device, not just backgrounded on the host: adb shell would
# otherwise take the server down with it when this script exits.
"$ADB" shell "run-as $APP_ID setsid nohup ./lldb-server platform --server \
    --listen 'unix-abstract:///$SOCKET' >/dev/null 2>&1 &" || true

for _ in 1 2 3 4 5 6 7 8 9 10; do
    "$ADB" shell run-as "$APP_ID" pgrep -f lldb-server >/dev/null 2>&1 && break
    sleep 0.3
done
"$ADB" shell run-as "$APP_ID" pgrep -f lldb-server >/dev/null 2>&1 \
    || die "lldb-server did not start — try \`$ADB shell run-as $APP_ID ./lldb-server --version\`"

# --- the app ----------------------------------------------------------------

# A session that ends without detaching cleanly — LLDB killed, VS Code quit mid
# ---attach — leaves the app SIGSTOPped in state T rather than running. It still
# has a pid, so nothing below would notice; wake it before anything else.
STATE="$("$ADB" shell "ps -A -o S,NAME | grep -w $APP_ID" 2>/dev/null | awk '{print $1}' | head -1 | tr -d '\r' || true)"
if [[ "$STATE" == T ]]; then
    echo "the app was left stopped by an earlier session — resuming it"
    "$ADB" shell run-as "$APP_ID" kill -CONT "$("$ADB" shell pidof "$APP_ID" | tr -d '\r' | awk '{print $1}')" || true
fi

if (( RESTART )) || ! "$ADB" shell pidof "$APP_ID" >/dev/null 2>&1; then
    if (( RESTART )); then "$ADB" shell am force-stop "$APP_ID"; fi
    echo "starting $APP_ID"
    "$ADB" shell am start -n "$APP_ID/$PKG.MainActivity" >/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        "$ADB" shell pidof "$APP_ID" >/dev/null 2>&1 && break
        sleep 0.5
    done
fi

PID="$("$ADB" shell pidof "$APP_ID" | tr -d '\r' | awk '{print $1}' || true)"
[[ -n "$PID" ]] || die "$APP_ID is not running"

# --- the VS Code side -------------------------------------------------------

# Generated rather than committed: the app id carries this worktree's name (see
# Android/app/build.gradle.kts), so one checked-in launch.json would be wrong in
# every other worktree. .vscode/ is git-ignored for that reason.
#
# The `process handle` line is what makes the session usable: ART raises SIGSEGV
# for its own implicit null checks and SIGQUIT/SIGUSR for GC and ANR dumps, many
# times a second, and LLDB halts on every one of them by default. It runs as a
# postRunCommand because there is no process to configure until the attach is
# done. (`SIGPWR` is in every Android LLDB recipe online and this LLDB rejects
# the name outright, taking the rest of the line with it — leave it out.)
#
# `timeout` is not optional in practice: lldb-dap gives an attach 30 s to reach a
# stopped process, and a cold attach here spends longer than that pulling the
# app's ~400 shared objects off the device. It fails with "process failed to stop
# within 30 s" — on a *warm* ~/.lldb module cache the same config attaches in
# seconds, which is what makes this look intermittent.
#
# Do NOT add `process continue` here. lldb-dap requires the process to still be
# stopped when postRunCommands finish — it installs breakpoints and completes its
# handshake afterwards — and resuming makes it abort the session with "Expected
# process to be stopped [...] check that any debugger command scripts are not
# resuming the process". Attaching leaves the app paused; press Continue once.
# Written only when the content actually changes: the setup task below runs this
# script, so every F5 rewrites these files while VS Code is reading them.
write_if_changed() {
    local path="$1" tmp
    tmp="$(mktemp)"
    cat > "$tmp"
    if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then
        rm -f "$tmp"
    else
        mv "$tmp" "$path"
    fi
}

mkdir -p "$ROOT/.vscode"

write_if_changed "$ROOT/.vscode/settings.json" <<EOF
{
    "lldb-dap.executable-path": "$LLDB_DAP"
}
EOF


# Two tasks and a wrapper, because F5 has to do two things this script owns:
# make sure the app and lldb-server are up (otherwise the attach fails with
# "could not find a process"), and bring up the log stream.
#
# `logs.sh -c` clears the device buffer first, so a session starts on an empty
# terminal instead of replaying the previous run.
#
# The banner is load-bearing. A background task only releases the debugger once
# its `endsPattern` matches a line, and logs.sh prints nothing at all until the
# app logs something — so matching on log output hangs F5 behind "Waiting for
# preLaunchTask" whenever the app is quiet. Echoing a line we control and
# matching *that* makes it deterministic.
write_if_changed "$ROOT/.vscode/tasks.json" <<EOF
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Android debug session",
            "dependsOrder": "sequence",
            "dependsOn": ["Android debug setup", "Android logs"],
            "problemMatcher": []
        },
        {
            "label": "Android debug setup",
            "type": "shell",
            "command": "\${workspaceFolder}/Scripts/Android/debug.sh --no-build",
            "presentation": {
                "panel": "dedicated",
                "reveal": "silent",
                "clear": true
            },
            "problemMatcher": []
        },
        {
            "label": "Android logs",
            "type": "shell",
            "command": "echo '— log stream ready —'; exec \${workspaceFolder}/Scripts/Android/logs.sh -c",
            "isBackground": true,
            "presentation": {
                "panel": "dedicated",
                "reveal": "always",
                "focus": false,
                "clear": true
            },
            "problemMatcher": {
                "pattern": {
                    "regexp": "^(?!x)x\$"
                },
                "background": {
                    "activeOnStart": true,
                    "beginsPattern": "^(?!x)x\$",
                    "endsPattern": "log stream ready"
                }
            }
        }
    ]
}
EOF

write_if_changed "$ROOT/.vscode/launch.json" <<EOF
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "lldb-dap",
            "request": "attach",
            "name": "Swift (Android)",
            "preLaunchTask": "Android debug session",
            "enableAutoVariableSummaries": true,
            "timeout": 300,
            "debugAdapterEnv": {
                "PATH": "$SDK/platform-tools:/usr/bin:/bin",
                "ANDROID_SERIAL": "$SERIAL"
            },
            "initCommands": [
                "platform select remote-android",
                "platform connect unix-abstract-connect:///$SOCKET"
            ],
            "attachCommands": [
                "process attach --name $APP_ID"
            ],
            "postRunCommands": [
                "process handle -p true -s false -n false SIGSEGV SIGBUS SIGXCPU SIGQUIT SIGUSR1 SIGUSR2"
            ],
            "exitCommands": [
                "detach"
            ]
        }
    ]
}
EOF

cat <<EOF

ready — $APP_ID is running as pid $PID
  lldb-dap     $LLDB_DAP
  lldb-server  ${LLDB_SERVER#"$NDK"/} (in the app sandbox)
  wrote        .vscode/settings.json, launch.json, tasks.json

In VS Code: open $ROOT, set a breakpoint in a .swift file, then
Run ▸ Swift (Android). The first attach pulls the app's shared objects off the
device and takes a minute; later ones hit LLDB's module cache.

lldb-server outlives the app and the attach is by name, so restarting the app
costs you nothing but another F5. Re-run this script after a rebuild, or after
the emulator restarts. For Kotlin, attach Android Studio separately — see
--help.
EOF
