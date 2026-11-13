#!/bin/bash
#
# Stream this app's own logs out of a running Android emulator or device.
#
# The app is far noisier than its own logging: a typical minute is dominated by
# `SkipWeb.WebView` resource lines and `chromium`. So this filters by tag rather
# than by pid — which also means it keeps streaming across an app restart, where
# a `--pid=` filter would go silent.
#
# Lines from a *sibling worktree's* app are then dropped by uid, because the tag
# alone cannot tell them apart: see "sibling worktrees" below.
#
# Usage: Scripts/Android/logs.sh [--local|--remote] [-a] [-c] [-d] [--color=MODE]
#                                [extra-tag…]
#
#   --local     this host's emulator; by default the remote PC's when it is
#               available (Scripts/Android/android-target.sh)
#   --remote    the remote PC's emulator, or fail
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
FOREIGN_UIDS=""
ARGS=(-v time)
EXTRA_TAGS=()
TARGET=auto

while (( $# )); do
    case "$1" in
        -h|--help)   sed -n '3,29p' "$0" | cut -c3-; exit 0 ;;
        -a|--all)    ALL=1 ;;
        --local|--remote)  TARGET="${1#--}" ;;
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
# shellcheck source=Scripts/Android/adb-state.sh
source "$(dirname "${BASH_SOURCE[0]}")/adb-state.sh"
[[ -x "$ADB" ]] || die "$ADB is missing — run \`skip android sdk install\`"

# shellcheck source=Scripts/Android/android-target.sh
source "$(dirname "${BASH_SOURCE[0]}")/android-target.sh"
select_android_target "$TARGET"

[[ "$(adb_state)" == device ]] \
    || die "no device — run Scripts/Android/start-emulator.sh (or set ANDROID_SERIAL)"

# Value of a Skip.env key, ignoring the `//`-commented lines.
skip_env() {
    sed -nE "s@^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*@\1@p" "$ROOT/Skip.env" | head -1
}

# The distribution stash overrides the app id, so read it rather than
# assuming the placeholder com.example.id1234.
APP_ID="$(skip_env ANDROID_APPLICATION_ID)"
[[ -n "$APP_ID" ]] || APP_ID="$(skip_env PRODUCT_BUNDLE_IDENTIFIER)"
[[ -n "$APP_ID" ]] || die "no app id in $ROOT/Skip.env"

# The debug build carries a per-worktree suffix (Android/app/build.gradle.kts);
# a release or distribution install does not.
WORKTREE="$(basename "$ROOT")"
SUFFIXED="$APP_ID.${WORKTREE//[^A-Za-z0-9_]/_}"

# Skip.env only names the id of the *current* tree: a release APK built with the
# distribution stash (ceylo.FurAffinity) is installed under an id it no longer holds.
MAIN_ACTIVITY="$(skip_env ANDROID_PACKAGE_NAME).MainActivity"
OWN_IDS=("$SUFFIXED" "$APP_ID")
while IFS= read -r id; do
    [[ "$id" == "$APP_ID."* || "$id" == "$APP_ID" ]] || OWN_IDS+=("$id")
done < <("$ADB" shell cmd package query-activities --components \
            -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 2>/dev/null \
         | tr -d '\r' | awk -F/ -v main="$MAIN_ACTIVITY" '$2 == main { print $1 }')

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

# Drops the lines whose app UID is in "$1" (space separated), then renders the
# prefix the way plain `-v time` would.
#
# This runs under `-v uid`, which prints "<time> <level>/<tag>(<uid>:<pid>): ". A
# uid is the *installed package*, so it still names the owner of a line whose
# process has since exited or restarted — which the pid alone does not, and
# restarting is exactly what a sibling under development does. The uid is then
# stripped back out: once the foreign lines are gone every survivor carries the
# same one, and archived logs and the summarisers keep the prefix they know.
#
# A tag never contains "(", so the first "(" in the line is always this field.
own_lines() {
    awk -v foreign="$1" '
        BEGIN { n = split(foreign, a, " "); for (i = 1; i <= n; i++) drop[a[i]] = 1 }
        {
            open = index($0, "(")
            end = index($0, "): ")
            if (open > 0 && end > open) {
                field = substr($0, open + 1, end - open - 1)
                colon = index(field, ":")
                if (colon > 0) {
                    uid = substr(field, 1, colon - 1)
                    gsub(/[^0-9]/, "", uid)
                    if (uid in drop) next
                    $0 = substr($0, 1, open) substr(field, colon + 1) substr($0, end)
                }
            }
            print; fflush()
        }
    '
}

# Runs logcat through the two optional filters: sibling worktrees out, then the
# repaint unless adb or the caller already settled the colors. `cat` stands in for
# a filter that has nothing to do, so the pipeline stays one expression.
logcat() {
    "$ADB" logcat "$@" \
        | { if [[ -n "$FOREIGN_UIDS" ]]; then own_lines "$FOREIGN_UIDS"; else cat; fi; } \
        | { if [[ "$COLOR" == prefix || "$COLOR" == level ]]; then colorize "$COLOR"; else cat; fi; }
}

(( CLEAR )) && "$ADB" logcat -c

# --- everything from the app process ----------------------------------------

if (( ALL )); then
    app_pid() {
        { "$ADB" shell pidof "$1" 2>/dev/null || true; } | tr -d '\r' | awk '{print $1}'
    }

    PID=""
    for id in "${OWN_IDS[@]}"; do
        PID="$(app_pid "$id")"
        [[ -n "$PID" ]] && break
    done
    [[ -n "$PID" ]] || die "none of ${OWN_IDS[*]} is running — launch it with \`Scripts/Android/run.sh\`"

    logcat "${ARGS[@]}" --pid="$PID" "${EXTRA_TAGS[@]}"
    exit
fi

# --- our tags only ----------------------------------------------------------

# PersistentLogger tags as "<subsystem>/<category>", and every module's subsystem
# is the installed applicationId (FALogSubsystem, installed at startup).
# "FurAffinity" is FALogSubsystem.fallback, what a process that installs no override
# logs under — the `skip android test` runner, whose output is worth seeing here too.
TAGS=()
for id in "${OWN_IDS[@]}" FurAffinity; do
    TAGS+=("$id/FA" "$id/FAKit" "$id/FAPages")
done

# The Kotlin bridges log under their own tags. logcat's -s takes no wildcards,
# so collect them from the source instead of hardcoding a list that will drift.
while IFS= read -r tag; do
    [[ -n "$tag" ]] && TAGS+=("$tag")
done < <(grep -hoE 'val TAG[^=]*=[[:space:]]*"[^"]+"' \
    "$ROOT"/Android/app/src/main/kotlin/*.kt 2>/dev/null | cut -d'"' -f2 | sort -u)

# --- sibling worktrees ------------------------------------------------------
#
# Every worktree installs the same applicationId under its own suffix, and the
# tags above cannot separate two of them: FAKit's module-level logger freezes its
# subsystem before FurAffinityUIRoot.onInit installs FALogSubsystem.override, so
# *both* apps' FAKit lines — [CFREPAIR] and [CFDIAG] among them — come out under
# the `FurAffinity` fallback tag. Dropping that tag is therefore not an option:
# it carries our own repair vocabulary. Left unfiltered this inflates a
# measurement silently — one run read "challenges 12" where 10 belonged to a
# worktree that merely happened to be running.
#
# So filter by the installed package's uid instead, which `own_lines` reads off
# `-v uid`. Every FA app id but ours is foreign; a bare id (a release or
# distribution install) is ours.
FOREIGN_UIDS="$("$ADB" shell pm list packages -U 2>/dev/null | tr -d '\r' | awk \
    -v ours="$SUFFIXED" -v bare="$APP_ID" '
        {
            sub(/^package:/, "", $1)
            sub(/^uid:/, "", $2)
        }
        $1 == ours || $1 == bare { next }
        substr($1, 1, length(bare) + 1) == bare "." { printf "%s ", $2 }')"

[[ -n "$FOREIGN_UIDS" ]] && ARGS+=(-v uid)

logcat "${ARGS[@]}" -s "${TAGS[@]}" "${EXTRA_TAGS[@]}"
