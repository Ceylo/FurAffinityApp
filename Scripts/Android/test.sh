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
#
# Each run must report at least the case count below, so a run that silently
# finds no tests cannot pass. Raise a floor when tests are added.
#
# The root package tests build in their own scratch path, .build/android-test:
# in the shared .build they rewrite the skipstone plugin outputs the Gradle app
# build reads, and the next `run.sh` fails in Kotlin until those are wiped.
#
# XDG_CACHE_HOME: an `adb shell` process has none, so Foundation's caches
# directory resolves to an unwritable /.cache (the app gets context.cacheDir).
#
# On CI (GitHub sets CI), FA_NOISY_TIMING tells the tests the emulator's
# timing is noise: a latency budget there fails at random.

set -eo pipefail

FAKIT_MIN_TESTS=184
UI_MIN_TESTS=40

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK_ARGS=()
LOG_DIR=""

while (( $# )); do
    case "$1" in
        -h|--help)    sed -n '3,23p' "$0" | cut -c3-; exit 0 ;;
        --timeout)    LOCK_ARGS+=(--timeout "$2"); shift ;;
        --timeout=*)  LOCK_ARGS+=("$1") ;;
        --log-dir)    LOG_DIR="$2"; shift ;;
        --log-dir=*)  LOG_DIR="${1#*=}" ;;
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
        "${BASH_SOURCE[0]}" --log-dir "$LOG_DIR"
fi

# Runs `skip android test` in $1, logging to $2, and checks the Swift Testing
# summary reports at least $3 cases, all passed.
run() {
    local dir="$1" log="$2" min="$3"
    shift 3
    local name="${dir#"$ROOT"}"
    name="${name#/}"
    name="${name:-the root package}"
    echo; echo "==> skip android test in $name (log: $log)"
    local status=0
    ( cd "$dir" && skip android test --testing-library testing "$@" ) 2>&1 | tee "$log" || status=$?

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

# `skip android test` never runs Gradle, which is what normally generates the
# catalog entries the root package's resource bundle carries.
"$ROOT/Scripts/Android/generate-assets.sh" > /dev/null

CI_ENV=()
[[ -n "$CI" ]] && CI_ENV=(--env FA_NOISY_TIMING=1)

run "$ROOT/FAKit" "$LOG_DIR/FAKit.log" "$FAKIT_MIN_TESTS" "${CI_ENV[@]}"
run "$ROOT" "$LOG_DIR/FurAffinityUI.log" "$UI_MIN_TESTS" "${CI_ENV[@]}" \
    --scratch-path .build/android-test \
    --env XDG_CACHE_HOME=/data/local/tmp/FurAffinityUITests-cache
