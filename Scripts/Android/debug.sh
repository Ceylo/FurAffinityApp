#!/bin/bash
#
# Prepare a native Swift debugging session for this worktree's debug app.
#
# Installs a build that keeps its Swift symbols, starts lldb-server inside the
# app sandbox, and writes .vscode/ so F5 (Swift (Android)) attaches to it.
# See Android/docs/build-and-run.md § Attaching a Swift debugger.
#
# Usage: Scripts/Android/debug.sh [--no-build] [--restart] [--timeout SECONDS]
#
#   --no-build  skip the build and install, just (re)start lldb-server against
#               whatever is installed — only sound if that build had symbols
#   --restart   force-stop the app and start it again before attaching
#   --timeout   how long to wait for the emulator lock, default 1800s
#
# Needs a booted device (Scripts/Android/start-emulator.sh). Environment:
# ANDROID_HOME / ANDROID_SDK_ROOT (SDK location), ANDROID_SERIAL (which device),
# JAVA_HOME (Gradle's JDK), TOOLCHAINS_DIR (where to find a swift.org toolchain).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BUILD=1
RESTART=0
LOCK_ARGS=()

while (( $# )); do
    case "$1" in
        -h|--help)    sed -n '3,18p' "$0" | cut -c3-; exit 0 ;;
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

# LLDB's remote-android platform picks its device from ANDROID_SERIAL; pin the
# one set up here into launch.json.
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

# Host side: lldb-dap from a swift.org toolchain — Xcode's lacks the Android
# fixes that landed in Swift 6.3.
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

# Device side: the NDK's lldb-server for the device's ABI.
NDK="$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)"
[[ -n "$NDK" ]] || die "no NDK in $SDK/ndk — install one with \`skip android sdk install\`"

# NDK and Swift SDK arch names differ; the Swift SDK has no 32-bit x86.
case "$ABI" in
    arm64-v8a)    SERVER_ARCH=aarch64; SWIFT_ARCH=aarch64 ;;
    armeabi-v7a)  SERVER_ARCH=arm;     SWIFT_ARCH=armv7 ;;
    x86_64)       SERVER_ARCH=x86_64;  SWIFT_ARCH=x86_64 ;;
    x86)          SERVER_ARCH=i386;    SWIFT_ARCH= ;;
    *)            die "no lldb-server mapping for ABI $ABI" ;;
esac

LLDB_SERVER="$(ls "$NDK"/toolchains/llvm/prebuilt/*/lib/clang/*/lib/linux/"$SERVER_ARCH"/lldb-server 2>/dev/null | sort -V | tail -1)"
[[ -n "$LLDB_SERVER" ]] || die "no $SERVER_ARCH lldb-server under $NDK"

# --- the Swift SDK, so expressions compile ----------------------------------

# Without an SDK path and module path, LLDB compiles expressions against the host
# macOS SDK and `p`/`po` fail (docs § Inspecting values). Both come from the
# bundle's swift-sdk.json; the module path is the `android` directory *below* its
# swiftResourcesPath. Optional: breakpoints and `frame variable` work without.
SWIFT_SDK_PATH=""
SWIFT_MODULE_PATH=""
BUNDLE="$(ls -d "$HOME"/Library/org.swift.swiftpm/swift-sdks/*_android.artifactbundle/swift-android 2>/dev/null | sort -V | tail -1)"
if [[ -n "$SWIFT_ARCH" && -f "$BUNDLE/swift-sdk.json" ]]; then
    # Every API level of one arch names the same two roots, so the lowest will do.
    TRIPLE="$(plutil -extract targetTriples xml1 -o - "$BUNDLE/swift-sdk.json" 2>/dev/null \
        | sed -n "s@.*<key>\($SWIFT_ARCH-[^<]*\)</key>.*@\1@p" | sort -V | head -1)"
    if [[ -n "$TRIPLE" ]]; then
        sdk_root="$(plutil -extract "targetTriples.$TRIPLE.sdkRootPath" raw -o - "$BUNDLE/swift-sdk.json" 2>/dev/null || true)"
        resources="$(plutil -extract "targetTriples.$TRIPLE.swiftResourcesPath" raw -o - "$BUNDLE/swift-sdk.json" 2>/dev/null || true)"
        [[ -d "$BUNDLE/$sdk_root" ]] && SWIFT_SDK_PATH="$BUNDLE/$sdk_root"
        [[ -d "$BUNDLE/$resources/android" ]] && SWIFT_MODULE_PATH="$BUNDLE/$resources/android"
    fi
fi

# --- build and install ------------------------------------------------------

# The checks above are cheap, so they fail fast before queueing for the lock
# (and rerun once it is held).
if [[ -z "$FA_EMULATOR_LOCK_HELD" ]]; then
    export FA_EMULATOR_LOCK_HELD=1
    args=()
    (( BUILD )) || args+=(--no-build)
    (( RESTART )) && args+=(--restart) || true
    exec "$(dirname "${BASH_SOURCE[0]}")/with-emulator-lock.sh" "${LOCK_ARGS[@]}" \
        "${BASH_SOURCE[0]}" "${args[@]}"
fi

if (( BUILD )); then
    # lldb-server ignores an APK's last entry (llvm/llvm-project#173966), which
    # assembleDebug makes a .so; installing with testOnly re-packs it so a
    # manifest entry lands last.
    ( cd "$ROOT/Android" && ./gradlew :app:assembleDebug -PfaDebugSymbols )
    ( cd "$ROOT/Android" && ./gradlew :app:installDebug -PfaDebugSymbols \
        -Pandroid.injected.testOnly=true )

    "$(dirname "${BASH_SOURCE[0]}")/check-shared-globals.sh" debug \
        || die "shared globals are duplicated — the app above was installed anyway"
fi

"$ADB" shell pm path "$APP_ID" >/dev/null 2>&1 \
    || die "$APP_ID is not installed — run without --no-build"

# --- lldb-server, inside the app sandbox ------------------------------------

# Runs as the app's uid to ptrace it, so it lives in the app's data directory
# (`run-as` is the only way in on a non-rooted device).
SOCKET="$APP_ID/lldb.sock"

"$ADB" shell run-as "$APP_ID" pkill -f lldb-server >/dev/null 2>&1 || true

# 44 MB: push only when the staged copy (which survives reboots) differs in size.
STAGED=/data/local/tmp/lldb-server
want=$(stat -f%z "$LLDB_SERVER")
have=$("$ADB" shell "stat -c %s $STAGED 2>/dev/null" | tr -d '\r' || true)
if [[ "$want" != "$have" ]]; then
    echo "pushing lldb-server ($((want / 1024 / 1024)) MB)"
    "$ADB" push "$LLDB_SERVER" "$STAGED" >/dev/null
fi
# /data/local/tmp is drwxrwx--x: the app uid can only reach a world-readable file.
"$ADB" shell chmod 644 "$STAGED"
"$ADB" shell run-as "$APP_ID" cp "$STAGED" ./lldb-server
"$ADB" shell run-as "$APP_ID" chmod 700 ./lldb-server

# Three slashes: the socket name is the URL's path; with two, the app id parses
# as the host. setsid/nohup so the server outlives this adb shell.
"$ADB" shell "run-as $APP_ID setsid nohup ./lldb-server platform --server \
    --listen 'unix-abstract:///$SOCKET' >/dev/null 2>&1 &" || true

for _ in 1 2 3 4 5 6 7 8 9 10; do
    "$ADB" shell run-as "$APP_ID" pgrep -f lldb-server >/dev/null 2>&1 && break
    sleep 0.3
done
"$ADB" shell run-as "$APP_ID" pgrep -f lldb-server >/dev/null 2>&1 \
    || die "lldb-server did not start — try \`$ADB shell run-as $APP_ID ./lldb-server --version\`"

# --- the app ----------------------------------------------------------------

# A session that ended without detaching leaves the app SIGSTOPped (state T)
# with a live pid, which the checks below would take for running.
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

# Generated, not committed: the app id carries this worktree's name.
# Written only on change, since every F5 reruns this script while VS Code reads them.
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

# initCommands run before the target exists; it inherits these as defaults.
INIT_COMMANDS=""
if [[ -n "$SWIFT_SDK_PATH" && -n "$SWIFT_MODULE_PATH" ]]; then
    INIT_COMMANDS="                \"settings set target.sdk-path $SWIFT_SDK_PATH\",
                \"settings append target.swift-module-search-paths $SWIFT_MODULE_PATH\",
"
fi
# LLDB's Foundation formatters miss swift-foundation's pure-Swift URL. This
# relies on _SwiftURL's private layout; if it changes, use `p url.absoluteString`.
INIT_COMMANDS="$INIT_COMMANDS                \"type summary add --summary-string \\\"\${var._url._parseInfo.urlString}\\\" FoundationEssentials.URL\",
                \"platform select remote-android\",
                \"platform connect unix-abstract-connect:///$SOCKET\""

mkdir -p "$ROOT/.vscode"

write_if_changed "$ROOT/.vscode/settings.json" <<EOF
{
    "lldb-dap.executable-path": "$LLDB_DAP"
}
EOF

# F5 runs setup (app + lldb-server up), then the log stream. A background task
# only releases F5 once endsPattern matches, and logs.sh is silent while the app
# is, so match a banner we echo ourselves.
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

# timeout: a cold attach pulls ~400 modules and outlasts lldb-dap's 30 s default.
# postRunCommands: ART raises these signals in normal operation (SIGPWR is
# rejected by name and drops the whole line). Never `process continue` there:
# lldb-dap aborts unless the process is still stopped.
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
$INIT_COMMANDS
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

if [[ -n "$SWIFT_SDK_PATH" ]]; then
    SWIFT_SUMMARY="${SWIFT_SDK_PATH#"$BUNDLE"/} + ${SWIFT_MODULE_PATH#"$BUNDLE"/} (in ${BUNDLE##*/swift-sdks/})"
else
    SWIFT_SUMMARY="not found — breakpoints still work, \`p\`/\`po\` will not"
fi

cat <<EOF

ready — $APP_ID is running as pid $PID
  lldb-dap     $LLDB_DAP
  lldb-server  ${LLDB_SERVER#"$NDK"/} (in the app sandbox)
  swift sdk    $SWIFT_SUMMARY
  wrote        .vscode/settings.json, launch.json, tasks.json

In VS Code: open $ROOT, set a breakpoint in a .swift file, then F5
(Swift (Android)), and press Continue once attached. A cold first attach takes
minutes; later ones hit LLDB's module cache.

F5 restarts lldb-server and starts the app if needed. Re-run this script after a
build it did not make (run.sh strips symbols). For Kotlin, attach Android Studio
in Java/Kotlin mode.
EOF
