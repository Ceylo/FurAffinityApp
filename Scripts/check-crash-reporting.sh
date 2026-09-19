#!/bin/bash
#
# Prove a crash reaches Sentry symbolicated: build as shipping does (symbols
# uploaded), crash the app deliberately, relaunch so the SDK sends the report,
# fetch that exact event from the Sentry API and assert on its frames.
#
# Usage: Scripts/check-crash-reporting.sh ios|android [--no-build] [--out DIR] [case…]
#
#   case         CrashTestCase names (FurAffinity/Helpers/CrashTest.swift), or
#                `optOut`: crash with the setting off and expect no event.
#                Default: every case the platform has, then optOut.
#   --no-build   reuse the installed build (its symbols must already be uploaded)
#   --out DIR    where each event's JSON lands, default .build/crash-reporting
#
# Environment:
#   SENTRY_DSN          built into the app for the run, restored afterwards
#   SENTRY_AUTH_TOKEN   uploads symbols (org:ci is enough)
#   SENTRY_READ_TOKEN   reads events back (event:read, org:read); defaults to
#                       SENTRY_AUTH_TOKEN
#
# iOS runs a Release build on this worktree's simulator (Scripts/iOS/simulator.sh);
# Android the `profile` build type on the emulator — release code, but it honours
# the crash-test intent extras a release build ignores. See
# Android/docs/crash-reporting.md.

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "=== $*"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORG=ceylo
PROJECT=ceylo-furaffinity-app
API=https://de.sentry.io/api/0
SECRETS="$ROOT/FurAffinity/CrashReportingSecrets.swift"

PLATFORM="$1"; shift || true
[[ "$PLATFORM" == ios || "$PLATFORM" == android ]] || { sed -n '3,25p' "$0" | cut -c3-; exit 2; }

BUILD=1
OUT="$ROOT/.build/crash-reporting"
CASES=()
while (( $# )); do
    case "$1" in
        --no-build) BUILD=0 ;;
        --out)      OUT="$2"; shift ;;
        -*)         die "unknown option $1" ;;
        *)          CASES+=("$1") ;;
    esac
    shift
done
if (( ${#CASES[@]} == 0 )); then
    CASES=(swiftFatalError swiftForceUnwrapFAKit swiftBackgroundThread)
    [[ $PLATFORM == android ]] && CASES+=(kotlinException)
    CASES+=(optOut)
fi

READ_TOKEN="${SENTRY_READ_TOKEN:-$SENTRY_AUTH_TOKEN}"
[[ -n "$READ_TOKEN" ]] || die "SENTRY_READ_TOKEN (or SENTRY_AUTH_TOKEN) is not set"
command -v jq >/dev/null || die "jq is missing"
mkdir -p "$OUT"

# --- the case table ---------------------------------------------------------

# function | source file | marker file (for the line number)
expectation() {
    case "$1" in
        swiftFatalError)       echo "CrashTest.swiftFatalError|CrashTest.swift|FurAffinity/Helpers/CrashTest.swift" ;;
        swiftForceUnwrapFAKit) echo "CrashTestSite.forceUnwrapNil|CrashTestSite.swift|FAKit/Sources/FAKit/CrashTestSite.swift" ;;
        swiftBackgroundThread) echo "CrashTest.swiftBackgroundThread|CrashTest.swift|FurAffinity/Helpers/CrashTest.swift" ;;
        kotlinException)       echo "crashTest|FACrashReportingBridge.kt|Android/app/src/main/kotlin/FACrashReportingBridge.kt" ;;
        optOut)                echo "||" ;;
        *)                     die "unknown case $1" ;;
    esac
}
for c in "${CASES[@]}"; do expectation "$c" >/dev/null; done

marker_line() {
    grep -n "CRASH-TEST-SITE $1\$" "$ROOT/$2" | cut -d: -f1
}

# --- the DSN, for the length of the run --------------------------------------

if (( BUILD )); then
    [[ -n "$SENTRY_DSN" ]] || die "SENTRY_DSN is not set"
    [[ -n "$SENTRY_AUTH_TOKEN" ]] || die "SENTRY_AUTH_TOKEN is not set: the build must upload its symbols"
    git -C "$ROOT" diff --quiet -- "$SECRETS" || die "$SECRETS has local changes"
    trap 'git -C "$ROOT" checkout -- "$SECRETS"' EXIT
    trap 'exit 130' INT
    sed -i '' "s#static let dsn = \"Your Sentry DSN\"#static let dsn = \"$SENTRY_DSN\"#" "$SECRETS"
fi

# --- platform drivers -------------------------------------------------------

if [[ $PLATFORM == ios ]]; then
    UDID="$("$ROOT/Scripts/iOS/simulator.sh" --udid)"
    xcrun simctl bootstatus "$UDID" -b >/dev/null
    DERIVED="$ROOT/.build/crash-reporting-ios"
    PRODUCTS="$DERIVED/Build/Products/Release-iphonesimulator"

    if (( BUILD )); then
        step "Release build for the simulator"
        xcodebuild -project "$ROOT/FurAffinity.xcodeproj" -scheme FurAffinity -configuration Release \
            -destination "id=$UDID" -derivedDataPath "$DERIVED" build -quiet
        step "Uploading dSYMs"
        sentry-cli debug-files upload --include-sources -o "$ORG" -p "$PROJECT" --wait "$PRODUCTS"
    fi
    APP="$(ls -d "$PRODUCTS"/*.app | head -1)"
    BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
    RELEASE="$BUNDLE@$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist")"
    xcrun simctl install "$UDID" "$APP"

    # Launched without a debugger, which would swallow the crash.
    launch() {
        xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
        xcrun simctl launch "$UDID" "$BUNDLE" "$@" | awk '{print $NF}'
    }
    crash() { # case run-id enabled
        local pid
        pid="$(launch -FACrashTest "$1" -FACrashTestRun "$2" \
            -FACrashReportingEnabled "$([[ $3 == 1 ]] && echo YES || echo NO)")"
        wait_exit "$pid"
    }
    wait_exit() {
        for _ in $(seq 60); do kill -0 "$1" 2>/dev/null || return 0; sleep 1; done
        die "the app (pid $1) did not crash within 60 s"
    }
    relaunch() { launch >/dev/null; sleep 15; }
    # The override is written to the setting, so it has to be put back.
    restore_setting() { launch -FACrashReportingEnabled YES >/dev/null; sleep 10; }
else
    SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
    ADB="$SDK/platform-tools/adb"
    skip_env() {
        sed -nE "s@^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*@\1@p" "$ROOT/Skip.env" | head -1
    }
    APP_ID="$(skip_env ANDROID_APPLICATION_ID)"
    [[ -n "$APP_ID" ]] || APP_ID="$(skip_env PRODUCT_BUNDLE_IDENTIFIER)"
    WORKTREE="$(basename "$ROOT")"
    APP_ID="$APP_ID.${WORKTREE//[^A-Za-z0-9_]/_}"
    ACTIVITY="$APP_ID/$(skip_env ANDROID_PACKAGE_NAME).MainActivity"
    RELEASE="$APP_ID@$(skip_env MARKETING_VERSION)"

    if (( BUILD )); then
        step "profile build (uploads the .so files and the R8 mapping)"
        "$ROOT/Scripts/Android/run.sh" --profile
    fi

    # The lock is held across the whole run, not per command.
    if [[ -z "$FA_EMULATOR_LOCK_HELD" ]]; then
        export FA_EMULATOR_LOCK_HELD=1
        args=("$PLATFORM" --no-build --out "$OUT" "${CASES[@]}")
        trap - EXIT
        (( BUILD )) && git -C "$ROOT" checkout -- "$SECRETS"
        exec "$ROOT/Scripts/Android/with-emulator-lock.sh" "${BASH_SOURCE[0]}" "${args[@]}"
    fi

    launch() {
        "$ADB" shell am force-stop "$APP_ID"
        "$ADB" shell am start -W -n "$ACTIVITY" "$@" >/dev/null
    }
    set_setting() { # 1|0
        launch --ez faCrashReportingEnabled "$([[ $1 == 1 ]] && echo true || echo false)"
        sleep 3
    }
    crash() { # case run-id enabled
        # The setting is read when the app starts, so it is written one launch ahead.
        set_setting "$3"
        launch --es faCrashTest "$1" --es faCrashTestRun "$2"
        for _ in $(seq 60); do
            "$ADB" shell pidof "$APP_ID" >/dev/null || return 0
            sleep 1
        done
        die "the app did not crash within 60 s"
    }
    relaunch() { launch; sleep 15; }
    # Tombstones outlive the process: turning reporting back on must not send the
    # crash that happened while it was off, so the control relaunches enabled too.
    restore_setting() { set_setting 1; relaunch; }
fi

# --- Sentry -------------------------------------------------------------------

PROJECT_ID="$(curl -sf -H "Authorization: Bearer $READ_TOKEN" "$API/projects/$ORG/$PROJECT/" | jq -r .id)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != null ]] || die "cannot read project $ORG/$PROJECT — check the token's scopes"

event_ids() { # search query
    curl -sf -G -H "Authorization: Bearer $READ_TOKEN" "$API/organizations/$ORG/events/" \
        --data-urlencode "field=id" --data-urlencode "dataset=errors" \
        --data-urlencode "project=$PROJECT_ID" --data-urlencode "statsPeriod=1h" \
        --data-urlencode "query=$1" | jq -r '.data[].id'
}

# Waits up to 3 minutes for the first event, then 30 s more so a duplicate shows.
wait_events() { # search query, seconds
    local ids=""
    for _ in $(seq $(( $2 / 10 ))); do
        ids="$(event_ids "$1")"
        [[ -n "$ids" ]] && break
        sleep 10
    done
    [[ -n "$ids" ]] && { sleep 30; ids="$(event_ids "$1")"; }
    echo "$ids"
}

# Bad-symbolication markers Sentry records on the event itself.
BAD_ERRORS='["native_missing_dsym","native_bad_dsym","native_symbolicator_failed","native_missing_symbol","proguard_missing_mapping","proguard_missing_lineno"]'

check_event() { # case json function file line
    local c="$1" json="$2" fn="$3" file="$4" line="$5" fail=()

    local errors
    errors="$(jq -r --argjson bad "$BAD_ERRORS" '[.errors[]?.type | select(. as $t | $bad | index($t))] | join(",")' "$json")"
    [[ -z "$errors" ]] || fail+=("symbolication errors: $errors")

    # No location on the event. "Prevent Storing of IP Addresses" nulls
    # user.ip_address, but Sentry geocodes the address before scrubbing it and
    # keeps the result, so city/region/country survive unless the project's
    # advanced scrubbing rule removes $user.geo.**. Neither SDK ever sends this;
    # it is added server-side, so only a server-side rule can take it away, and
    # only a fresh event proves the rule is still in place. See
    # Android/docs/crash-reporting.md § Consent.
    local located
    located="$(jq -r '[(.user.geo // {}) | to_entries[] | select(.value != null)
                       | "\(.key)=\(.value)"] | join(", ")' "$json")"
    [[ -z "$located" ]] || fail+=("event carries a location: $located")
    [[ "$(jq -r '.user.ip_address // "null"' "$json")" == null ]] \
        || fail+=("event carries an IP address")

    # Nothing but the crash: both SDKs attach breadcrumbs by default. See
    # Android/docs/crash-reporting.md § No breadcrumbs.
    local crumbs
    crumbs="$(jq '[.entries[] | select(.type == "breadcrumbs") | .data.values[]?] | length' "$json")"
    [[ "$crumbs" == 0 ]] || fail+=("event carries $crumbs breadcrumbs")

    # The frame, wherever the event put the crashing stack. Its file and line are
    # also what catches a return of cross-module optimization: a copy of a FAKit
    # function inlined into the app carries no line table at all (Package.swift).
    local frame
    frame="$(jq -c --arg fn "$fn" --arg file "$file" '
        [(.entries[] | select(.type == "exception") | .data.values[].stacktrace.frames[]?),
         (.entries[] | select(.type == "threads") | .data.values[] | select(.crashed) | .stacktrace.frames[]?)]
        | map(select((.function // "") | contains($fn)) | select((.filename // "") | endswith($file)))
        | first // empty' "$json")"
    if [[ -z "$frame" ]]; then
        fail+=("no frame with function ~ $fn in $file")
    else
        [[ "$(jq -r .lineNo <<< "$frame")" == "$line" ]] || fail+=("line $(jq -r .lineNo <<< "$frame"), expected $line")
        [[ "$(jq -r .inApp <<< "$frame")" == true ]] || fail+=("frame not in_app")
        # Swift sources ride along with the debug files (--include-sources); the
        # Gradle plugin registers no source-bundle task for Kotlin, so a .kt frame
        # has the line but no text. See Android/docs/crash-reporting.md.
        if [[ "$file" == *.swift ]]; then
            jq -e --argjson l "$line" '[.context[]? | select(.[0] == $l) | .[1]] | first // "" | contains("CRASH-TEST-SITE")' \
                <<< "$frame" >/dev/null || fail+=("no source context at line $line")
        fi
    fi

    case "$c" in
        swiftBackgroundThread)
            # A crashed-thread record is only there when the SDK captured threads.
            jq -e '[.entries[] | select(.type == "threads") | .data.values[] | select(.crashed)]
                   | length == 0 or (.[0] | (.main != true) and (.name != "main") and (.id != 0))' "$json" >/dev/null \
                || fail+=("crashed on the main thread") ;;
        kotlinException)
            [[ "$(jq -r '.module // ""' <<< "$frame")" == fur.affinity.ui.FACrashReportingBridge ]] \
                || fail+=("frame module is not fur.affinity.ui.FACrashReportingBridge") ;;
    esac

    echo "  top frames:"
    jq -r '[(.entries[] | select(.type == "exception") | .data.values[-1].stacktrace.frames[]?)]
           | reverse | .[:5][] | "    \(.function // .symbol // "?")  \(.filename // "-"):\(.lineNo // "-")\(if .inApp then "  [app]" else "" end)"' "$json"

    if (( ${#fail[@]} )); then
        printf '  - %s\n' "${fail[@]}"
        return 1
    fi
}

# --- run ----------------------------------------------------------------------

RESULTS=()
FAILED=0
for c in "${CASES[@]}"; do
    RUN="$(uuidgen)"
    IFS='|' read -r fn file marker <<< "$(expectation "$c")"
    step "$c (run $RUN)"

    if [[ $c == optOut ]]; then
        # The run tag is never set with reporting off, so look for *any* event from
        # this build since the crash — one sent later would carry no tag.
        since="$(date -u +%Y-%m-%dT%H:%M:%S)"
        crash swiftFatalError "$RUN" 0
        relaunch
        restore_setting
        ids="$(wait_events "release:\"$RELEASE\" timestamp:>=$since" 180)"
        if [[ -z "$ids" ]]; then
            RESULTS+=("PASS  $c: no event in 3 min")
        else
            RESULTS+=("FAIL  $c: reported while opted out ($ids)"); FAILED=1
        fi
        continue
    fi

    line="$(marker_line "$c" "$marker")"
    [[ -n "$line" ]] || die "no CRASH-TEST-SITE $c marker in $marker"
    crash "$c" "$RUN" 1
    relaunch
    ids="$(wait_events "crash_test_run:$RUN" 180)"
    count="$(grep -c . <<< "$ids" || true)"
    if (( count == 0 )); then
        RESULTS+=("FAIL  $c: no event within 3 min"); FAILED=1
        continue
    fi

    id="$(head -1 <<< "$ids")"
    json="$OUT/crash-$PLATFORM-$c.json"
    curl -sf -H "Authorization: Bearer $READ_TOKEN" "$API/projects/$ORG/$PROJECT/events/$id/" > "$json"
    echo "  event $id → $json"
    if check_event "$c" "$json" "$fn" "$file" "$line" && (( count == 1 )); then
        RESULTS+=("PASS  $c: $fn $file:$line")
    else
        (( count == 1 )) || echo "  - $count events for one crash: $(tr '\n' ' ' <<< "$ids")"
        RESULTS+=("FAIL  $c"); FAILED=1
    fi
done

step "Summary ($PLATFORM)"
printf '%s\n' "${RESULTS[@]}"
exit $FAILED
