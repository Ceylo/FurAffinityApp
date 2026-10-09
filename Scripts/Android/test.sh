#!/bin/bash
#
# Run every Android test suite on the running emulator or device: FAKit's
# package (FAPages, FAKit, FALogging) and the root package's FurAffinityUITests,
# which are the FurAffinityTests files that build for Android.
#
# Usage: Scripts/Android/test.sh [--timeout SECONDS] [--log-dir DIR]
#
#   --timeout   how long to wait for the emulator lock, default 1800s
#   --log-dir   where the two runs' logs go, default a temporary directory
#   --base DIR  run from DIR, a copy of the worktree, rather than the worktree
#
# The tests build in a leased build slot, as Gradle builds do: this hands over
# to Gradle's faAndroidTest task, which holds the lease and calls back with
# --base. Where slots are off (CI, FA_ANDROID_SLOTS=0) they build in place.
#
# Each run must report at least the case count below, so a run that silently
# finds no tests cannot pass. Raise a floor when tests are added.
#
# Each package builds in its own scratch path under .build, android-test and
# android-test-fakit, which a clean (rm -rf .build) takes along. In .build itself
# they would rewrite the plugin outputs a Gradle build reads, and that build then
# fails in Kotlin until those are wiped.
#
# XDG_CACHE_HOME: an `adb shell` process has none, so Foundation's caches
# directory resolves to an unwritable /.cache (the app gets context.cacheDir).
#
# On CI (GitHub sets CI), FA_NOISY_TIMING tells the tests the emulator's
# timing is noise: a latency budget there fails at random.

set -eo pipefail

FAKIT_MIN_TESTS=189
UI_MIN_TESTS=59

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK_ARGS=()
LOG_DIR=""
BASE=""

while (( $# )); do
    case "$1" in
        -h|--help)    sed -n '3,29p' "$0" | cut -c3-; exit 0 ;;
        --timeout)    LOCK_ARGS+=(--timeout "$2"); shift ;;
        --timeout=*)  LOCK_ARGS+=("$1") ;;
        --log-dir)    LOG_DIR="$2"; shift ;;
        --log-dir=*)  LOG_DIR="${1#*=}" ;;
        --base)       BASE="$2"; shift ;;
        *)            die "unknown argument: $1" ;;
    esac
    shift
done

command -v skip >/dev/null || die "\`skip\` is not on PATH"
[[ -n "$LOG_DIR" ]] || LOG_DIR="$(mktemp -d -t fa-android-test)"
mkdir -p "$LOG_DIR"
LOG_DIR="$(cd "$LOG_DIR" && pwd)"

if [[ -z "$FA_EMULATOR_LOCK_HELD" ]]; then
    export FA_EMULATOR_LOCK_HELD=1
    exec "$(dirname "${BASH_SOURCE[0]}")/with-emulator-lock.sh" "${LOCK_ARGS[@]}" \
        "${BASH_SOURCE[0]}" --log-dir "$LOG_DIR" ${BASE:+--base "$BASE"}
fi

# Runs `skip android test` for suite $1 in $2, logging to $LOG_DIR/$1.log, and
# checks the Swift Testing summary reports at least $3 cases, all passed.
run() {
    local name="$1" dir="$2" min="$3"
    shift 3
    local log="$LOG_DIR/$name.log"
    echo; echo "==> skip android test in $name (log: $log)"
    local status=0
    # Native: under swiftbuild, `skip android test` runs only the first test target's
    # runner it finds, and FAKit has three.
    ( cd "$dir" && skip android test --testing-library testing --build-system native "$@" ) 2>&1 | tee "$log" || status=$?

    # The summary line, stripped of colour and the spinner's carriage returns.
    local summary
    summary="$(sed 's/\x1b\[[0-9;]*m//g' "$log" | tr '\r' '\n' \
        | grep -E 'Test run with [0-9]+ tests?' | tail -1 || true)"
    [[ -z "$summary" ]] || echo "$summary"
    (( status == 0 )) || die "$name: skip android test failed ($status)"
    [[ -n "$summary" ]] || die "$name: no Swift Testing summary in $log"

    local count
    count="$(sed -E 's/.*Test run with ([0-9]+) tests?.*/\1/' <<< "$summary")"
    (( count >= min )) || die "$name: $count tests ran, expected at least $min"
    [[ "$summary" == *" passed after "* ]] || die "$name: $summary"
}

if [[ -z "$BASE" ]]; then
    # As BuildSlotsPlugin's slotsEnabled(); faAndroidTest leases a slot and calls back with --base.
    if [[ "$FA_ANDROID_SLOTS" != 0 && -z "$CI" ]]; then
        # shellcheck source=Scripts/Android/java-home.sh
        source "$ROOT/Scripts/Android/java-home.sh"
        exec "$ROOT/Android/gradlew" -p "$ROOT/Android" faAndroidTest -PfaTestLogDir="$LOG_DIR"
    fi
    # `skip android test` never runs Gradle, which is what normally generates the
    # catalog entries the root package's resource bundle carries; a --base caller does.
    "$ROOT/Scripts/Android/generate-assets.sh" > /dev/null
    BASE="$ROOT"
fi

[[ "$BASE" == "$ROOT" ]] || echo "test.sh: building in $BASE"

CI_ENV=()
[[ -n "$CI" ]] && CI_ENV=(--env FA_NOISY_TIMING=1)

run FAKit "$BASE/FAKit" "$FAKIT_MIN_TESTS" "${CI_ENV[@]}" \
    --scratch-path ../.build/android-test-fakit
run FurAffinityUI "$BASE" "$UI_MIN_TESTS" "${CI_ENV[@]}" \
    --scratch-path .build/android-test \
    --env XDG_CACHE_HOME=/data/local/tmp/FurAffinityUITests-cache
