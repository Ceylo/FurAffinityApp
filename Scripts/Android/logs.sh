#!/bin/bash
#
# Stream this app's own logs out of a running Android emulator or device.
#
# The app is far noisier than its own logging: a typical minute is dominated by
# `SkipWeb.WebView` resource lines and `chromium`. So this filters by tag rather
# than by pid — which also means it keeps streaming across an app restart, where
# a `--pid=` filter would go silent.
#
# Usage: Scripts/Android/logs.sh [-a] [-c] [-d] [--color=MODE] [extra-tag…]
#
#   -a, --all       every line from the app process instead (WebView included);
#                   needs the app running, and stops when it restarts
#   -c, --clear     clear the log buffer before streaming
#   -d, --dump      print what is buffered and exit instead of following
#   --color=MODE    prefix (default) colors the timestamp/level/tag and leaves
#                   the message in the terminal's own foreground; level colors
#                   just the level letter; full is logcat's whole-line color;
#                   none disables it. Defaults to none when piped.
#
# Environment: ANDROID_HOME / ANDROID_SDK_ROOT (SDK location), ANDROID_SERIAL
# (which device, when several are attached).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ALL=0
CLEAR=0
COLOR=auto
ARGS=(-v time)
EXTRA_TAGS=()

while (( $# )); do
    case "$1" in
        -h|--help)   sed -n '3,22p' "$0" | cut -c3-; exit 0 ;;
        -a|--all)    ALL=1 ;;
        -c|--clear)  CLEAR=1 ;;
        -d|--dump)   ARGS+=(-d) ;;
        --color=*)   COLOR="${1#*=}" ;;
        --color)     COLOR="$2"; shift ;;
        -*)          die "unknown option $1 (see --help)" ;;
        *)           EXTRA_TAGS+=("$1") ;;
    esac
    shift
done

case "$COLOR" in
    auto)                    [[ -t 1 ]] && COLOR=prefix || COLOR=none ;;
    prefix|level|full|none)  ;;
    *)                       die "--color takes prefix, level, full or none" ;;
esac

[[ "$COLOR" == full ]] && ARGS+=(-v color)

# --- locate the SDK ---------------------------------------------------------

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
[[ -x "$ADB" ]] || die "$ADB is missing — run \`skip android sdk install\`"

"$ADB" get-state >/dev/null 2>&1 \
    || die "no device — run Scripts/Android/start-android-emulator.sh (or set ANDROID_SERIAL)"

# Value of a Skip.env key, ignoring the `//`-commented lines.
skip_env() {
    sed -nE "s@^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*@\1@p" "$ROOT/Skip.env" | head -1
}

# --- partial coloring -------------------------------------------------------

# logcat's own -v color paints the whole line, message included. This repaints
# "<time> <level>/<tag>(<pid>):" in the level's color and leaves the message on
# the terminal's foreground. Splitting on the first "): " and the first "/" is
# what keeps a message full of colons and slashes (URLs, mostly) intact.
colorize() {
    awk -v mode="$1" '
        BEGIN {
            c["V"] = "90"; c["D"] = "34"; c["I"] = "32"
            c["W"] = "33"; c["E"] = "31"; c["F"] = "1;31"
            reset = "\033[0m"
        }
        {
            end = index($0, "): ")
            slash = index($0, "/")
            if (end == 0 || slash < 2 || slash > end) { print; fflush(); next }

            level = substr($0, slash - 1, 1)
            if (!(level in c)) { print; fflush(); next }

            paint = "\033[" c[level] "m"
            message = substr($0, end + 3)

            if (mode == "level")
                print substr($0, 1, slash - 2) paint level reset substr($0, slash, end - slash + 2) " " message
            else
                print paint substr($0, 1, end + 1) reset " " message
            fflush()
        }
    '
}

# Runs logcat, repainting unless adb or the caller already settled the colors.
logcat() {
    if [[ "$COLOR" == prefix || "$COLOR" == level ]]; then
        "$ADB" logcat "$@" | colorize "$COLOR"
    else
        "$ADB" logcat "$@"
    fi
}

(( CLEAR )) && "$ADB" logcat -c

# --- everything from the app process ----------------------------------------

if (( ALL )); then
    # The distribution stash overrides the app id, so read it rather than
    # assuming the placeholder com.example.id1234.
    APP_ID="$(skip_env ANDROID_APPLICATION_ID)"
    [[ -n "$APP_ID" ]] || APP_ID="$(skip_env PRODUCT_BUNDLE_IDENTIFIER)"
    [[ -n "$APP_ID" ]] || die "no app id in $ROOT/Skip.env"

    app_pid() {
        "$ADB" shell pidof "$1" 2>/dev/null | tr -d '\r' | awk '{print $1}'
    }

    # The debug build carries a per-worktree suffix (Android/app/build.gradle.kts);
    # a release or distribution install does not, so fall back to the bare id.
    WORKTREE="$(basename "$ROOT")"
    SUFFIXED="$APP_ID.${WORKTREE//[^A-Za-z0-9_]/_}"

    PID="$(app_pid "$SUFFIXED")"
    if [[ -n "$PID" ]]; then
        APP_ID="$SUFFIXED"
    else
        PID="$(app_pid "$APP_ID")"
    fi
    [[ -n "$PID" ]] || die "neither $SUFFIXED nor $APP_ID is running — launch it with \`Scripts/Android/run-android.sh\`"

    logcat "${ARGS[@]}" --pid="$PID" "${EXTRA_TAGS[@]}"
    exit
fi

# --- our tags only ----------------------------------------------------------

# PersistentLogger tags as "<subsystem>/<category>". The app module's subsystem
# is its Android package name; FAKit's Bundle.main.bundleIdentifier is nil there,
# so it falls back to the literal "FurAffinity".
PKG="$(skip_env ANDROID_PACKAGE_NAME)"
[[ -n "$PKG" ]] || die "no ANDROID_PACKAGE_NAME in $ROOT/Skip.env"

TAGS=("$PKG/FA" FurAffinity/FAKit FurAffinity/FAPages)

# The Kotlin bridges log under their own tags. logcat's -s takes no wildcards,
# so collect them from the source instead of hardcoding a list that will drift.
while IFS= read -r tag; do
    [[ -n "$tag" ]] && TAGS+=("$tag")
done < <(sed -nE 's@.*\bTAG[[:space:]]*=[[:space:]]*"([^"]+)".*@\1@p' \
    "$ROOT"/Android/app/src/main/kotlin/*.kt 2>/dev/null | sort -u)

logcat "${ARGS[@]}" -s "${TAGS[@]}" "${EXTRA_TAGS[@]}"
