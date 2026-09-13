#!/bin/bash
#
# Record a profile of this worktree's running `profile` build on the emulator.
#
# Install that build first with `Scripts/Android/run.sh --profile`: a debug build's
# -Onone Swift and debuggable ART runtime put the time in the wrong places. Every
# recording lands in .build/profiles/<timestamp>-<command>/, and the script says
# how to open it. See Android/docs/profiling.md.
#
# Usage: Scripts/Android/profile.sh <command> [options] [--timeout SECONDS]
#
#   cpu [--duration S] [--fp] [--launch]
#       simpleperf, default 20 s, DWARF call graphs (--fp: frame pointers — cheaper,
#       but shallower through code built without them). Writes profile.json.gz for
#       https://profiler.firefox.com, Swift names demangled. --launch restarts the
#       app under the profiler, to record its startup: a process that starts after
#       recording begins is otherwise not followed.
#   trace [--duration S] [--native-heap] [--compose]
#       Perfetto: scheduling, app sections, per-process RSS every 250 ms, frame
#       timeline — fa.pftrace, the whole device. Also writes signposts.pftrace,
#       only the app's FAKit/FAPages signposts, CPU use per 100 ms and memory
#       (focus-trace.py), and prints a summary. Both open in https://ui.perfetto.dev.
#       --native-heap adds heapprofd allocation samples; --compose, a section per
#       composable (thousands of them).
#   mem [--interval S]
#       `dumpsys meminfo` into meminfo.csv, S seconds apart (default 2). Type a
#       label and Enter to tag the next sample; Ctrl-C to stop.
#
#   --timeout   how long to wait for the emulator lock, default 1800s
#
# Environment: ANDROID_HOME / ANDROID_SDK_ROOT (SDK location), ANDROID_SERIAL
# (which device), TOOLCHAINS_DIR (where to find a swift.org toolchain).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

COMMAND=""
DURATION=20
INTERVAL=2
CALL_GRAPH="-g"
NATIVE_HEAP=0
LAUNCH=0
COMPOSE=0
ARGS=()
LOCK_ARGS=()

while (( $# )); do
    case "$1" in
        -h|--help)      sed -n '3,32p' "$0" | cut -c3-; exit 0 ;;
        cpu|trace|mem)  [[ -z "$COMMAND" ]] || die "one command at a time"; COMMAND="$1" ;;
        --duration)     DURATION="$2"; ARGS+=("$1" "$2"); shift ;;
        --interval)     INTERVAL="$2"; ARGS+=("$1" "$2"); shift ;;
        --fp)           CALL_GRAPH="--call-graph fp"; ARGS+=("$1") ;;
        --native-heap)  NATIVE_HEAP=1; ARGS+=("$1") ;;
        --launch)       LAUNCH=1; ARGS+=("$1") ;;
        --compose)      COMPOSE=1; ARGS+=("$1") ;;
        --timeout)      LOCK_ARGS+=(--timeout "$2"); shift ;;
        --timeout=*)    LOCK_ARGS+=("$1") ;;
        *)              die "unknown argument: $1 (see --help)" ;;
    esac
    shift
done

[[ -n "$COMMAND" ]] || die "which recording? cpu, trace or mem (see --help)"
(( LAUNCH == 0 )) || [[ "$COMMAND" == cpu ]] || die "--launch is a cpu option"
(( COMPOSE == 0 )) || [[ "$COMMAND" == trace ]] || die "--compose is a trace option"
[[ "$DURATION" =~ ^[0-9]+$ ]] || die "--duration takes a number of seconds"
# Whole seconds: macOS's bash 3.2 `read -t` takes nothing finer.
[[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]] || die "--interval takes a whole number of seconds"

# --- locate the SDK and the tools -------------------------------------------

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
[[ -x "$ADB" ]] || die "$ADB is missing — run \`skip android sdk install\`"
export ANDROID_HOME="$SDK"

NDK="$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)"
[[ -n "$NDK" ]] || die "no NDK in $SDK/ndk — install one with \`skip android sdk install\`"

if [[ "$COMMAND" == cpu ]]; then
    [[ -f "$NDK/simpleperf/app_profiler.py" ]] || die "no simpleperf scripts under $NDK"
    command -v python3 >/dev/null || die "simpleperf's scripts need python3"

    # Same search as debug.sh's lldb-dap: a swift.org toolchain, then Xcode's.
    TC_DIR="${TOOLCHAINS_DIR:-$HOME/Library/Developer/Toolchains}"
    DEMANGLE=""
    for tc in "$TC_DIR/swift-latest.xctoolchain" "$TC_DIR"/swift-*.xctoolchain \
              /Library/Developer/Toolchains/swift-latest.xctoolchain; do
        [[ -x "$tc/usr/bin/swift-demangle" ]] || continue
        DEMANGLE="$tc/usr/bin/swift-demangle"
        break
    done
    [[ -n "$DEMANGLE" ]] || DEMANGLE="$(xcrun --find swift-demangle 2>/dev/null || true)"
    [[ -n "$DEMANGLE" ]] || die "no swift-demangle — install Xcode or a swift.org toolchain"

    # The APK's libraries are stripped; the merged, unstripped ones carry .symtab.
    LIBS="$(ls -d "$ROOT"/.build/Android/app/intermediates/merged_native_libs/profile/*/out/lib/arm64-v8a 2>/dev/null | head -1)"
    [[ -n "$LIBS" ]] || die "no unstripped profile libraries — run Scripts/Android/run.sh --profile"

    # -dontobfuscate keeps class names, but R8 still merges classes and moves static
    # methods between them; the mapping puts them back where the source has them.
    MAPPING="$ROOT/.build/Android/app/outputs/mapping/profile/mapping.txt"
fi

# --- require a booted device ------------------------------------------------

[[ "$("$ADB" get-state 2>/dev/null | tr -d '\r')" == device ]] \
    || die "no device — run Scripts/Android/start-emulator.sh (or set ANDROID_SERIAL)"

[[ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] \
    || die "the device is still booting — Scripts/Android/start-emulator.sh waits for it"

# --- what to record ---------------------------------------------------------

# Value of a Skip.env key, ignoring the `//`-commented lines.
skip_env() {
    sed -nE "s@^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*@\1@p" "$ROOT/Skip.env" | head -1
}

# Same derivation as run.sh: the profile build installs under the debug app's id.
APP_ID="$(skip_env ANDROID_APPLICATION_ID)"
[[ -n "$APP_ID" ]] || APP_ID="$(skip_env PRODUCT_BUNDLE_IDENTIFIER)"
[[ -n "$APP_ID" ]] || die "no app id in $ROOT/Skip.env"

WORKTREE="$(basename "$ROOT")"
APP_ID="$APP_ID.${WORKTREE//[^A-Za-z0-9_]/_}"

PKG="$(skip_env ANDROID_PACKAGE_NAME)"
[[ -n "$PKG" ]] || die "no ANDROID_PACKAGE_NAME in $ROOT/Skip.env"

# run-as admits only a debuggable app, and names the reason otherwise — one cheap
# call where `dumpsys package` takes seconds on a busy emulator.
if RUN_AS="$("$ADB" shell run-as "$APP_ID" true 2>&1)"; then
    die "$APP_ID is a debug build, which would skew every number — run Scripts/Android/run.sh --profile"
fi
[[ "$RUN_AS" == *"not debuggable"* ]] \
    || die "$APP_ID is not installed — run Scripts/Android/run.sh --profile (run-as: ${RUN_AS//$'\r'/})"

# --- take the lock ----------------------------------------------------------

# Another worktree's build on the same host would steal the emulator's CPU.
if [[ -z "$FA_EMULATOR_LOCK_HELD" ]]; then
    export FA_EMULATOR_LOCK_HELD=1
    exec "$(dirname "${BASH_SOURCE[0]}")/with-emulator-lock.sh" "${LOCK_ARGS[@]}" \
        "${BASH_SOURCE[0]}" "$COMMAND" "${ARGS[@]}"
fi

PID="$("$ADB" shell pidof "$APP_ID" 2>/dev/null | tr -d '\r' | awk '{print $1}' || true)"
[[ -n "$PID" ]] || (( LAUNCH )) \
    || die "$APP_ID is not running — start it (Scripts/Android/run.sh --profile does)"

OUT="$ROOT/.build/profiles/$(date +%Y%m%d-%H%M%S)-$COMMAND"
mkdir -p "$OUT"
cd "$OUT"

# --- cpu --------------------------------------------------------------------

record_cpu() {
    echo "recording CPU samples for ${DURATION}s — use the app now"
    # cpu-clock: the emulator exposes no hardware counters.
    local launch=()
    (( LAUNCH )) && launch=(-a "$PKG.MainActivity")
    # Its adb pushes are logged as warnings, one per library.
    python3 "$NDK/simpleperf/app_profiler.py" -p "$APP_ID" "${launch[@]}" --ndk_path "$NDK" \
        -lib "$LIBS" -o perf.data \
        -r "-e cpu-clock -f 4000 $CALL_GRAPH --duration $DURATION" 2>&1 \
        | sed -l -e '/file pushed/d' -e '/^$/d'

    echo "converting to the Firefox Profiler format"
    local mapping=()
    [[ -f "$MAPPING" ]] && mapping=(--proguard-mapping-file "$MAPPING")
    python3 "$NDK/simpleperf/gecko_profile_generator.py" -i perf.data --symfs binary_cache \
        "${mapping[@]}" \
        | "$DEMANGLE" --simplified \
        | gzip > profile.json.gz

    cat <<EOF

wrote $OUT/profile.json.gz
Open https://profiler.firefox.com, then "Load a profile from file".
EOF
}

# --- trace ------------------------------------------------------------------

record_trace() {
    local device_trace=/data/misc/perfetto-traces/fa.pftrace

    # Compose emits a section per composable only once told to, per process.
    if (( COMPOSE )); then
        "$ADB" shell am broadcast -a androidx.tracing.perfetto.action.ENABLE_TRACING \
            "$APP_ID/androidx.tracing.perfetto.TracingReceiver" >/dev/null \
            || echo "warning: could not enable composition tracing; composables will not show" >&2
    fi

    {
        cat <<EOF
buffers { size_kb: 131072 fill_policy: RING_BUFFER }
buffers { size_kb: 8192 fill_policy: RING_BUFFER }
duration_ms: $(( DURATION * 1000 ))
data_sources {
  config {
    name: "linux.ftrace"
    target_buffer: 0
    ftrace_config {
      ftrace_events: "sched/sched_switch"
      ftrace_events: "sched/sched_waking"
      ftrace_events: "sched/sched_process_exit"
      ftrace_events: "sched/sched_process_free"
      ftrace_events: "task/task_newtask"
      ftrace_events: "task/task_rename"
      atrace_categories: "view"
      atrace_categories: "gfx"
      atrace_categories: "am"
      atrace_categories: "dalvik"
      atrace_apps: "$APP_ID"
    }
  }
}
data_sources {
  config {
    name: "linux.process_stats"
    target_buffer: 1
    process_stats_config {
      scan_all_processes_on_start: true
      record_thread_names: true
      proc_stats_poll_ms: 250
    }
  }
}
data_sources {
  config {
    name: "android.surfaceflinger.frametimeline"
    target_buffer: 1
  }
}
EOF
        if (( NATIVE_HEAP )); then
            cat <<EOF
data_sources {
  config {
    name: "android.heapprofd"
    target_buffer: 0
    heapprofd_config {
      sampling_interval_bytes: 4096
      process_cmdline: "$APP_ID"
      shmem_size_bytes: 8388608
      block_client: true
    }
  }
}
EOF
        fi
    } > config.pbtxt

    echo "tracing for ${DURATION}s — use the app now"
    "$ADB" shell rm -f "$device_trace"
    "$ADB" shell perfetto --txt -c - -o "$device_trace" < config.pbtxt
    "$ADB" pull "$device_trace" fa.pftrace >/dev/null
    "$ADB" shell rm -f "$device_trace"

    echo
    python3 "$ROOT/Scripts/Android/focus-trace.py" fa.pftrace "$APP_ID" -o signposts.pftrace \
        | tee signposts.txt \
        || echo "warning: could not focus the trace; fa.pftrace is intact" >&2

    cat <<EOF

wrote $OUT/
  signposts.pftrace  the app's signposts and memory only — start here
  fa.pftrace         the whole device: scheduling, every process, frame timeline
Open https://ui.perfetto.dev, then "Open trace file". Signposts are slices on the
thread that ran them; memory is the "mem.rss" counters under the app's process.
EOF
}

# --- mem --------------------------------------------------------------------

# Columns of `dumpsys meminfo`'s App Summary, in KB (1024 bytes).
MEM_ROWS=("Java Heap" "Native Heap" "Code" "Stack" "Graphics" "Private Other" "System")

# KB → the largest 1024-based unit that keeps the value at least 1: "512 KB", "196.4 MB".
human_size() {
    awk -v kb="$1" 'BEGIN {
        if (kb == "") { print "-"; exit }
        split("B KB MB GB TB", unit, " ")
        v = kb * 1024; i = 1
        while (v >= 1024 && i < 5) { v /= 1024; i++ }
        printf(i <= 2 ? "%d %s" : "%.1f %s", v, unit[i])
    }'
}

record_mem() {
    # The CSV keeps raw numbers so a spreadsheet can plot them; the unit is in the header.
    local header="time,label" row
    for row in "${MEM_ROWS[@]}"; do header+=",$row PSS (KB)"; done
    header+=",TOTAL PSS (KB),TOTAL RSS (KB)"
    echo "$header" > meminfo.csv

    trap 'printf "\nwrote %s\n" "$OUT/meminfo.csv"; exit 0' INT

    cat <<EOF
sampling $APP_ID every ${INTERVAL}s — type a label and Enter to tag the next sample, Ctrl-C to stop

  time      when the sample was taken (host clock)
  java      Java Heap PSS: ART's managed heap, i.e. Kotlin and Java objects
  native    Native Heap PSS: malloc'd memory, i.e. Swift objects, C/C++ buffers
  graphics  Graphics PSS: GPU textures and buffers (0 on the emulator)
  pss       TOTAL PSS: all the app's memory, shared pages split among their users
  rss       TOTAL RSS: all the app's resident pages, shared ones counted in full
  label     text typed before this sample
Sizes are 1024-based; every App Summary row is in $OUT/meminfo.csv, in KB.

EOF
    printf '%-8s %10s %10s %10s %10s %10s  %s\n' time java native graphics pss rss label

    local label=""
    while true; do
        local info time line values total_pss total_rss
        # dumpsys gives a service 10 s by default, which a loaded emulator overruns.
        info="$("$ADB" shell dumpsys -t 30 meminfo "$APP_ID" 2>/dev/null | tr -d '\r')"
        time="$(date +%H:%M:%S)"

        # The summary rows are "<name>: <Pss> <Rss>"; the Pss column comes first.
        values=()
        for row in "${MEM_ROWS[@]}"; do
            line="$(awk -v r="$row:" '/App Summary/ { s = 1 } s && index($0, r) { sub(".*" r, ""); print $1; exit }' <<< "$info")"
            values+=("${line:-}")
        done
        total_pss="$(awk '/App Summary/ { s = 1 } s && /TOTAL PSS:/ { sub(/.*TOTAL PSS:/, ""); print $1; exit }' <<< "$info")"
        total_rss="$(awk '/App Summary/ { s = 1 } s && /TOTAL RSS:/ { sub(/.*TOTAL RSS:/, ""); print $1; exit }' <<< "$info")"

        if [[ "$info" == *"DUMP TIMEOUT"* ]]; then
            echo "$time  dumpsys timed out — the emulator is overloaded" >&2
        elif [[ -z "$total_pss" ]]; then
            echo "$time  no meminfo — did the app exit?" >&2
        else
            local csv_label="${label//\"/\"\"}"
            (IFS=,; echo "$time,\"$csv_label\",${values[*]},$total_pss,$total_rss") >> meminfo.csv
            # values: 0 Java Heap, 1 Native Heap, 4 Graphics.
            printf '%-8s %10s %10s %10s %10s %10s  %s\n' "$time" \
                "$(human_size "${values[0]}")" "$(human_size "${values[1]}")" \
                "$(human_size "${values[4]}")" "$(human_size "$total_pss")" \
                "$(human_size "$total_rss")" "$label"
        fi

        # A timeout returns >128; anything else (stdin closed) would spin, so wait.
        label=""
        read -r -t "$INTERVAL" label || { (( $? > 128 )) || sleep "$INTERVAL"; label=""; }
    done
}

case "$COMMAND" in
    cpu)    record_cpu ;;
    trace)  record_trace ;;
    mem)    record_mem ;;
esac
