#!/bin/bash
#
# Remove a merged worktree and everything it left behind outside its directory.
#
# `git worktree remove` takes the worktree's own .build/ and Gradle output, but
# not what is keyed by its path or name elsewhere: its emulator debug app, its
# `FA <name>` simulator, its DerivedData dirs (the Skip Xcode project's have no
# info.plist, so nothing can tell whose they are but the path hash), its
# XcodeBuildMCP workspace and its tokens in the Android build slots. This
# removes the worktree first, so a removal git refuses leaves everything else in
# place, then all of them, then its branch. The slots themselves stay: any
# worktree reuses them.
#
# Usage: Scripts/cleanup-worktree.sh [--dry-run] [--force] [--base <branch>]… <worktree name|path>…
#        Scripts/cleanup-worktree.sh [--dry-run] [--reclaim] --orphans
#
#   --dry-run   print what would be removed, and its size, without removing it
#   --force     remove an unmerged worktree and branch (a squash-merged one);
#               a worktree with changes is refused regardless
#   --base      a branch the worktree's must be merged into; repeatable,
#               replaces the default `android` and `main`
#   --orphans   sweep what worktrees removed without this script left behind,
#               list what it kept and what still uses it, and total the storage
#               of each branch; it assumes every checkout is a worktree of this repo.
#               It also reports the Android build slots, slot tokens of removed
#               worktrees, and the per-worktree .build/{plugins,checkouts,
#               repositories,arm64-apple-ios} that builds in a slot leave unused
#   --reclaim   with --orphans, also delete those tokens and unused directories
#
# A bare name is a directory under ../FurAffinity-worktrees. The worktree may
# already be gone (ExitWorktree, `git worktree remove`): its leftovers are still
# found. Run it from inside the worktree being removed if you like — it re-runs
# from a temporary copy, and your shell is then in a deleted directory.
#
# Shared caches (~/.gradle, SwiftPM, ModuleCache.noindex) are left alone: they
# are content-addressed or self-pruning, and not any one worktree's.
#
# Environment: ANDROID_HOME / ANDROID_SDK_ROOT (SDK location), ANDROID_SERIAL
# (which device, when several are attached), FA_ANDROID_SLOTS_DIR (the build
# slots' parent, default ~/Library/Developer/Xcode/DerivedData).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }

ROOT="${FA_CLEANUP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"

DRY_RUN=0
FORCE=0
ORPHANS=0
RECLAIM=0
BASES=()
TARGETS=()

while (( $# )); do
    case "$1" in
        -h|--help)   sed -n '3,42p' "$0" | cut -c3-; exit 0 ;;
        --dry-run)   DRY_RUN=1 ;;
        --force)     FORCE=1 ;;
        --orphans)   ORPHANS=1 ;;
        --reclaim)   RECLAIM=1 ;;
        --base)      [[ -n "$2" ]] || die "--base takes a branch"; BASES+=("$2"); shift ;;
        --base=*)    BASES+=("${1#*=}") ;;
        --)          shift; TARGETS+=("$@"); break ;;
        -*)          die "unknown option $1 (see --help)" ;;
        *)           TARGETS+=("$1") ;;
    esac
    shift
done

# Never removed, whatever --base says.
PROTECTED=(android main)
(( ${#BASES[@]} )) || BASES=("${PROTECTED[@]}")

if (( ORPHANS )); then
    (( ${#TARGETS[@]} == 0 )) || die "--orphans takes no worktree"
else
    (( ${#TARGETS[@]} )) || die "no worktree given (see --help)"
    (( ! RECLAIM )) || die "--reclaim goes with --orphans"
fi

# --- where things are -------------------------------------------------------

COMMON="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)" \
    || die "$ROOT is not in a git repository"
MAIN="$(cd "$(dirname "$COMMON")" && pwd -P)"
WORKTREES="$(dirname "$MAIN")/FurAffinity-worktrees"

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
MCP_WORKSPACES="$HOME/Library/Developer/XcodeBuildMCP/workspaces"
SIM_DEVICES="$HOME/Library/Developer/CoreSimulator/Devices"
SLOTS_DIR="${FA_ANDROID_SLOTS_DIR:-$DERIVED_DATA}"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
LOCK_SCRIPT="${FA_CLEANUP_LOCK:-$ROOT/Scripts/Android/with-emulator-lock.sh}"

# Subdirectories an agent may start XcodeBuildMCP in, or Xcode may open as a package.
SUBDIRS=(FAKit FALogging Android Darwin FurAffinity)

git_main() { git -C "$MAIN" "$@"; }

# Absolute path for a worktree argument: a bare name lives in $WORKTREES.
target_path() {
    local arg="${1%/}"
    if [[ "$arg" != */* && "$arg" != . && "$arg" != .. ]]; then
        echo "$WORKTREES/$arg"
    elif [[ -d "$arg" ]]; then
        (cd "$arg" && pwd -P)
    elif [[ -d "$(dirname "$arg")" ]]; then
        # git records worktrees by physical path.
        echo "$(cd "$(dirname "$arg")" && pwd -P)/$(basename "$arg")"
    elif [[ "$arg" == /* ]]; then
        echo "$arg"
    else
        echo "$PWD/$arg"
    fi
}

# --- re-run from a copy when inside a worktree being removed ----------------

if (( ! ORPHANS )) && [[ -z "$FA_CLEANUP_REEXEC" ]]; then
    HERE="$(pwd -P)"
    RESOLVED=()
    INSIDE=0
    for t in "${TARGETS[@]}"; do
        wt="$(target_path "$t")"
        RESOLVED+=("$wt")
        [[ "$ROOT/" == "$wt/"* || "$HERE/" == "$wt/"* ]] && INSIDE=1
    done

    if (( INSIDE )); then
        TMP="$(mktemp -d "${TMPDIR:-/tmp}/fa-cleanup.XXXXXX")"
        cp "${BASH_SOURCE[0]}" "$TMP/cleanup-worktree.sh"
        [[ -x "$LOCK_SCRIPT" ]] && cp "$LOCK_SCRIPT" "$TMP/with-emulator-lock.sh"
        ARGS=()
        (( DRY_RUN )) && ARGS+=(--dry-run)
        (( FORCE )) && ARGS+=(--force)
        for b in "${BASES[@]}"; do ARGS+=(--base "$b"); done
        cd "$MAIN"
        FA_CLEANUP_REEXEC="$TMP" FA_CLEANUP_ROOT="$MAIN" FA_CLEANUP_LOCK="$TMP/with-emulator-lock.sh" \
            FA_CLEANUP_CALLER_DIR="$HERE" \
            exec bash "$TMP/cleanup-worktree.sh" "${ARGS[@]}" -- "${RESOLVED[@]}"
    fi
fi

[[ -n "$FA_CLEANUP_REEXEC" ]] && trap 'rm -rf "$FA_CLEANUP_REEXEC"' EXIT

# --- helpers ----------------------------------------------------------------

contains() {
    local needle="$1"; shift
    local x
    for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
    return 1
}

# Reads paths on stdin and prints "<key> <path>" for each. `dd`: Xcode's
# DerivedData hash — md5, each 8-byte half a big-endian uint64 written as 14
# letters a–z. `mcp`: XcodeBuildMCP's workspace key (build/utils/workspace-identity.js).
# `suffix`: the applicationIdSuffix Android/app/build.gradle.kts derives from
# the basename — java.util.regex, like python's re, replaces per code point.
PATH_KEYS_PY='
import hashlib, os, re, sys
mode = sys.argv[1]
for p in sys.stdin.read().splitlines():
    if mode == "dd":
        digest, out = hashlib.md5(p.encode()).digest(), ""
        for half in (digest[:8], digest[8:]):
            n, s = int.from_bytes(half, "big"), ""
            for _ in range(14):
                s, n = chr(97 + n % 26) + s, n // 26
            out += s
    elif mode == "suffix":
        out = re.sub(r"[^A-Za-z0-9_]", "_", os.path.basename(p))
    else:
        slug = re.sub(r"[^A-Za-z0-9._-]+", "-", os.path.basename(p) or "workspace")
        slug = re.sub(r"^[.-]+|[.-]+$", "", slug)[:64] or "workspace"
        out = slug + "-" + hashlib.sha256(p.encode()).hexdigest()[:12]
    print(out, p)
'

# Sets KEYS and KEY_PATHS from `compute_keys <mode> <newline-separated paths>`.
# Dies rather than return short: an empty list would read as "nothing is live".
compute_keys() {
    local out key path
    KEYS=() KEY_PATHS=()
    [[ -n "$2" ]] || return 0
    out="$(printf '%s\n' "$2" | python3 -c "$PATH_KEYS_PY" "$1")" || die "python3 failed hashing paths"
    while read -r key path; do KEYS+=("$key"); KEY_PATHS+=("$path"); done <<< "$out"
    (( ${#KEYS[@]} == $(printf '%s\n' "$2" | wc -l) )) || die "hashed fewer paths than given"
}

# The candidate paths whose hash names a worktree's DerivedData dirs.
derived_data_paths() {
    local wt="$1" sub
    echo "$wt"
    echo "$wt/FurAffinity.xcodeproj"
    echo "$wt/Project.xcworkspace"
    echo "$wt/Darwin/FurAffinityUI.xcodeproj"
    for sub in FAKit FALogging; do echo "$wt/$sub"; done
}

# And those XcodeBuildMCP may have been started in.
mcp_roots() {
    local wt="$1" sub
    echo "$wt"
    for sub in "${SUBDIRS[@]}"; do echo "$wt/$sub"; done
}

human() {
    awk -v k="$1" 'BEGIN {
        if (k >= 1048576) printf "%.1f GB", k / 1048576
        else if (k >= 1024) printf "%.0f MB", k / 1024
        else printf "%d KB", k
    }'
}

TOTAL_KB=0
FAILED=0
CALLER_REMOVED=0

# du's size even when it fails partway (a build rewriting the tree, a missing dir).
size_kb() {
    local kb
    kb="$(du -sk "$1" 2>/dev/null | cut -f1)" || true
    echo "${kb:-0}"
}

# Remove a file tree, reporting its size.
remove_tree() {
    local path="$1" label="$2" kb
    kb="$(size_kb "$path")"
    TOTAL_KB=$(( TOTAL_KB + kb ))
    if (( DRY_RUN )); then
        echo "  would remove $label ($(human "$kb"))"
    elif rm -rf "$path"; then
        echo "  removed $label ($(human "$kb"))"
    else
        TOTAL_KB=$(( TOTAL_KB - kb ))
        warn "could not remove all of $label"; FAILED=1
    fi
}

# --- the emulator app -------------------------------------------------------

# Value of a Skip.env key, ignoring the `//`-commented lines (as run.sh reads it).
skip_env_values() {
    sed -nE 's@^[[:space:]]*(ANDROID_APPLICATION_ID|PRODUCT_BUNDLE_IDENTIFIER)[[:space:]]*=[[:space:]]*([^[:space:]]+).*@\2@p'
}

# Every app-id prefix a debug build may have used: each live checkout's
# Skip.env, the bases', and the distribution stash's.
app_prefixes() {
    # `|| true`: main has no Skip.env, and errexit would end the whole group there.
    {
        local wt ref sha
        while IFS= read -r wt; do
            [[ -f "$wt/Skip.env" ]] && skip_env_values < "$wt/Skip.env"
        done < <(git_main worktree list --porcelain | sed -n 's/^worktree //p')
        for ref in "${BASES[@]}"; do
            git_main show "$ref:Skip.env" 2>/dev/null | skip_env_values || true
        done
        sha="$(git_main stash list --format='%H %gs' | sed -n 's/ .*For App Store distribution$//p' | head -1)"
        if [[ -n "$sha" ]]; then git_main show "$sha:Skip.env" 2>/dev/null | skip_env_values || true; fi
    } | sort -u
}

EMULATOR=unknown
PACKAGES=()
PREFIXES=()

load_emulator() {
    [[ "$EMULATOR" == unknown ]] || return 0
    local p
    while IFS= read -r p; do [[ -n "$p" ]] && PREFIXES+=("$p"); done < <(app_prefixes)
    if [[ -x "$ADB" && "$("$ADB" get-state 2>/dev/null | tr -d '\r')" == device \
        && "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
        EMULATOR=up
        while IFS= read -r p; do PACKAGES+=("$p"); done \
            < <("$ADB" shell pm list packages 2>/dev/null | tr -d '\r' | sed -n 's/^package://p')
    else
        EMULATOR=down
    fi
}

# Sets APP_KB to an installed app's APK plus data, and APP_SIZE to it for
# display. Its data is only readable through run-as, so a debug build's.
app_size() {
    local apk data
    read -r apk data < <("$ADB" shell "d=\$(pm path '$1' | sed -n '1s/^package://p');
        du -sk \"\${d%/*}\" 2>/dev/null | cut -f1 | tr '\n' ' ';
        run-as '$1' du -sk . 2>/dev/null | cut -f1" | tr -d '\r' | tr '\n' ' ') || true
    APP_KB=$(( ${apk:-0} + ${data:-0} ))
    APP_SIZE="$(human "$APP_KB")"
    [[ -n "$data" ]] || APP_SIZE="$APP_SIZE APK, data unreadable"
}

uninstall_app() {
    local id="$1"
    app_size "$id"
    TOTAL_KB=$(( TOTAL_KB + APP_KB ))
    if (( DRY_RUN )); then
        echo "  would uninstall $id ($APP_SIZE)"
        return
    fi
    local lock=()
    if [[ -x "$LOCK_SCRIPT" ]]; then
        lock=("$LOCK_SCRIPT")
    else
        warn "no $LOCK_SCRIPT — uninstalling without the emulator lock"
    fi
    if "${lock[@]}" "$ADB" uninstall "$id" >/dev/null; then
        echo "  uninstalled $id ($APP_SIZE)"
    else
        TOTAL_KB=$(( TOTAL_KB - APP_KB ))
        warn "could not uninstall $id"; FAILED=1
    fi
}

# The app and, if on-device tests ran, its instrumentation APK.
clean_emulator_app() {
    local suffix="$WT_SUFFIX" prefix id found=0
    load_emulator
    if [[ "$EMULATOR" == down ]]; then
        for prefix in "${PREFIXES[@]}"; do
            warn "no booted emulator (or several, without ANDROID_SERIAL) — later: adb uninstall $prefix.$suffix"
        done
        return
    fi
    for prefix in "${PREFIXES[@]}"; do
        for id in "$prefix.$suffix" "$prefix.$suffix.test"; do
            if contains "$id" "${PACKAGES[@]}"; then
                uninstall_app "$id"
                found=1
            fi
        done
    done
    (( found )) || echo "  no emulator app"
}

# --- the simulator ----------------------------------------------------------

# SIMS: "<udid>|<state>|<name>" for every `FA <name>` device, listed once
# (simctl takes ~0.3 s) — a run only ever deletes devices it has listed.
SIMS=()
SIMS_LOADED=0
load_simulators() {
    (( SIMS_LOADED )) && return 0
    SIMS_LOADED=1
    local line
    while IFS= read -r line; do SIMS+=("$line"); done < <(
        xcrun simctl list devices 2>/dev/null \
            | sed -nE 's@^[[:space:]]*FA (.+) \(([0-9A-Fa-f-]{36})\) \(([A-Za-z ]+)\).*@\2|\3|\1@p'
    )
}

remove_simulator() {
    local udid="$1" state="$2" name="$3" kb
    kb="$(size_kb "$SIM_DEVICES/$udid")"
    TOTAL_KB=$(( TOTAL_KB + kb ))
    if (( DRY_RUN )); then
        echo "  would delete simulator FA $name ($(human "$kb"))"
        return
    fi
    [[ "$state" == Shutdown ]] || xcrun simctl shutdown "$udid" 2>/dev/null || true
    if xcrun simctl delete "$udid"; then
        echo "  deleted simulator FA $name ($(human "$kb"))"
    else
        TOTAL_KB=$(( TOTAL_KB - kb ))
        warn "could not delete simulator FA $name"; FAILED=1
    fi
}

clean_simulator() {
    local name="$1" line udid state sim found=0
    load_simulators
    # Matching the whole name is what keeps `FA android` from also taking
    # `FA android-ci`.
    for line in "${SIMS[@]}"; do
        IFS='|' read -r udid state sim <<< "$line"
        if [[ "$sim" == "$name" ]]; then
            remove_simulator "$udid" "$state" "$sim"
            found=1
        fi
    done
    (( found )) || echo "  no simulator"
}

# --- DerivedData and XcodeBuildMCP -----------------------------------------

workspace_path() { plutil -extract WorkspacePath raw -o - "$1/info.plist" 2>/dev/null || true; }

clean_derived_data() {
    local wt="$1" dir path found=0
    compute_keys dd "$(derived_data_paths "$wt")"
    for dir in "$DERIVED_DATA"/*-*; do
        [[ -d "$dir" && "$(basename "$dir")" != android-slot-* ]] || continue
        if contains "${dir##*-}" "${KEYS[@]}" \
            || { path="$(workspace_path "$dir")"; [[ -n "$path" && "$path/" == "$wt/"* ]]; }; then
            remove_tree "$dir" "DerivedData/$(basename "$dir")"
            found=1
        fi
    done
    (( found )) || echo "  no DerivedData"
}

clean_mcp_workspaces() {
    local wt="$1" key found=0
    compute_keys mcp "$(mcp_roots "$wt")"
    for key in "${KEYS[@]}"; do
        if [[ -d "$MCP_WORKSPACES/$key" ]]; then
            remove_tree "$MCP_WORKSPACES/$key" "XcodeBuildMCP workspace $key"
            found=1
        fi
    done
    (( found )) || echo "  no XcodeBuildMCP workspace"
}

# --- Android build slots ----------------------------------------------------

# A worktree's token in each slot it built in is .slot-tokens/<sha1 of its path>
# (Android/build-slots). Left behind, a new worktree at that path would take it
# for a deleted .build and wipe the slot's.
slot_token_name() { printf %s "$1" | shasum -a1 | cut -d' ' -f1; }

clean_slot_tokens() {
    local wt="$1" token slot found=0
    token="$(slot_token_name "$wt")"
    for slot in "$SLOTS_DIR"/android-slot-*; do
        # Properties escapes with a backslash.
        if [[ "$(sed -n 's/^owner=//p' "$slot/.slot-state" 2>/dev/null | sed 's/\\\(.\)/\1/g')" == "$wt" ]]; then
            echo "  kept $(basename "$slot"), which it built in last: any worktree reuses it"
        fi
        [[ -f "$slot/.slot-tokens/$token" ]] || continue
        if (( DRY_RUN )); then
            echo "  would remove its token in $(basename "$slot")"
        elif rm -f "$slot/.slot-tokens/$token"; then
            echo "  removed its token in $(basename "$slot")"
        else
            warn "could not remove its token in $(basename "$slot")"; FAILED=1
        fi
        found=1
    done
    (( found )) || echo "  no Android build slot token"
}

# Prints, per slot, "slot<TAB>path<TAB>idle|busy<TAB>owner<TAB>lastUsed ms", then
# "token<TAB>path" for each token whose worktree is not among the paths on stdin.
# Builds lock a slot with a POSIX lock (Java's FileChannel), probed here as
# Scripts/Android/clean.sh takes it, under the pool lock so that the probe can't
# make a starting build pass the slot over.
SLOTS_PY='
import fcntl, hashlib, os, re, sys
pool_dir = sys.argv[1]
live = {hashlib.sha1(p.encode()).hexdigest() for p in sys.stdin.read().splitlines()}
slots = sorted(
    (int(m.group(1)), os.path.join(pool_dir, n)) for n in os.listdir(pool_dir)
    if (m := re.fullmatch(r"android-slot-([1-9][0-9]*)", n)) and os.path.isdir(os.path.join(pool_dir, n))
)
if not slots:
    sys.exit(0)
pool = open(os.path.join(pool_dir, ".android-slot-pool.lock"), "a")
fcntl.lockf(pool, fcntl.LOCK_EX)
for _, slot in slots:
    with open(os.path.join(slot, ".lock"), "a") as lock:
        try:
            fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            state = "idle"
        except OSError:
            state = "busy"
    props = {}
    try:
        with open(os.path.join(slot, ".slot-state"), encoding="latin-1") as f:
            for line in f:
                key, sep, value = line.rstrip("\n").partition("=")
                if sep and not key.startswith("#"):
                    props[key] = re.sub(r"\\(?:u([0-9a-fA-F]{4})|(.))",
                        lambda m: chr(int(m[1], 16)) if m[1] else m[2], value)
    except OSError:
        pass
    print("slot", slot, state, props.get("owner", ""), props.get("lastUsed", "0"), sep="\t")
    tokens = os.path.join(slot, ".slot-tokens")
    for t in sorted(os.listdir(tokens)) if os.path.isdir(tokens) else []:
        if re.fullmatch(r"[0-9a-f]{40}", t) and t not in live:
            print("token", os.path.join(tokens, t), sep="\t")
'

# The slots, kept whatever their owner: any worktree reuses them, and
# FA_ANDROID_SLOTS_MAX already caps them. Clean.sh --all deletes the idle ones.
report_slots() {
    local out kind path state owner used kb lines=() label when found=0
    [[ -d "$SLOTS_DIR" ]] || return 0
    out="$(printf '%s\n' "${LIVE[@]}" | python3 -c "$SLOTS_PY" "$SLOTS_DIR")" \
        || die "python3 failed reading the Android build slots"
    echo "Android build slots (any worktree reuses them; Scripts/Android/clean.sh --all deletes the idle ones)"
    while IFS=$'\t' read -r kind path state owner used; do
        [[ -n "$kind" ]] || continue
        if [[ "$kind" == token ]]; then
            label="token $(basename "$(dirname "$(dirname "$path")")")/.slot-tokens/$(basename "$path")"
            if (( ! RECLAIM )); then
                lines+=("  kept $label — its worktree is gone (--reclaim removes it)")
            elif (( DRY_RUN )); then
                echo "  would remove $label, of a removed worktree"; found=1
            elif rm -f "$path"; then
                echo "  removed $label, of a removed worktree"; found=1
            else
                warn "could not remove $path"; FAILED=1
            fi
            continue
        fi
        kb="$(size_kb "$path")"
        when="never used"
        [[ "$used" =~ ^[0-9]+$ ]] && (( used > 0 )) \
            && when="last used $(date -r $(( used / 1000 )) '+%Y-%m-%d %H:%M')"
        [[ -z "$owner" || -d "$owner" ]] || owner="$owner (gone)"
        lines+=("  kept $(basename "$path") ($(human "$kb")) — $state, $when${owner:+ by $(tilde "$owner")}")
    done <<< "$out"
    end_section_lines "$found" "${lines[@]}"
}

# What the prebuild left in each checkout's .build before its Swift side moved to
# a slot. A branch without Android/build-slots still builds there, as does
# build-release-apk.sh, which recreates them.
report_legacy_build() {
    local i wt dirs names d kb found=0 lines=()
    echo "Legacy Android .build directories"
    for i in "${!LIVE[@]}"; do
        wt="${LIVE[$i]}" dirs=() names="" kb=0
        for d in plugins checkouts repositories arm64-apple-ios; do
            [[ -d "$wt/.build/$d" ]] || continue
            dirs+=("$wt/.build/$d") names+="${names:+,}$d"
            kb=$(( kb + $(size_kb "$wt/.build/$d") ))
        done
        (( ${#dirs[@]} )) || continue
        names="$(basename "$wt")/.build/{$names}"
        if [[ ! -d "$wt/Android/build-slots" ]]; then
            lines+=("  kept $names ($(human "$kb")) — in use: ${LIVE_BRANCHES[$i]} predates build slots")
        elif (( RECLAIM )); then
            for d in "${dirs[@]}"; do remove_tree "$d" "$(basename "$wt")/.build/$(basename "$d")"; done
            found=1
        else
            lines+=("  kept $names ($(human "$kb")) — unused: it builds in a slot (--reclaim removes it)")
        fi
    done
    end_section_lines "$found" "${lines[@]}"
}

end_section_lines() {
    local found="$1"
    shift
    KEPT=("$@")
    end_section "$found"
}

# --- one worktree -----------------------------------------------------------

# Sets WT_REGISTERED, WT_LOCKED, WT_BRANCH and WT_HEAD from `git worktree list`,
# WT_SUFFIX to its app id suffix, and WT_NAMESAKE to another live checkout whose
# name gives the same one.
read_worktree() {
    local wt="$1" line cur="" others="" i
    WT_REGISTERED=0 WT_LOCKED=0 WT_BRANCH="" WT_HEAD="" WT_NAMESAKE=""
    while IFS= read -r line; do
        case "$line" in
            "worktree "*) cur="${line#worktree }"
                          [[ "$cur" != "$wt" && -d "$cur" ]] && others+=$'\n'"$cur" ;;
            "HEAD "*)     [[ "$cur" == "$wt" ]] && WT_HEAD="${line#HEAD }" ;;
            "branch "*)   [[ "$cur" == "$wt" ]] && WT_BRANCH="${line#branch refs/heads/}" ;;
            locked*)      [[ "$cur" == "$wt" ]] && WT_LOCKED=1 ;;
        esac
        [[ "$cur" == "$wt" ]] && WT_REGISTERED=1
    done < <(git_main worktree list --porcelain)
    compute_keys suffix "$wt$others"
    WT_SUFFIX="${KEYS[0]}"
    for (( i = 1; i < ${#KEYS[@]}; i++ )); do
        [[ "${KEYS[$i]}" == "${KEYS[0]}" ]] && WT_NAMESAKE="${KEY_PATHS[$i]}"
    done
    return 0
}

# Ignored files that must not go with the worktree: keystores, certificates,
# profiles and the Sentry token — real files, not the links to another copy.
signing_material() {
    local f
    git -C "$1" ls-files --others --ignored --exclude-standard --directory 2>/dev/null \
        | while IFS= read -r f; do
            case "$(basename "$f")" in
                *.jks|*.keystore|keystore.properties|*.p12|*.mobileprovision|.sentryclirc)
                    [[ -L "$1/$f" ]] || echo "$f" ;;
            esac
        done
}

# Refuses (non-zero) when removing the worktree would lose work; --force
# waives only the merge check.
gate() {
    local wt="$1" tip base
    local changes material
    if [[ -d "$wt" ]] && (( WT_REGISTERED )); then
        if ! changes="$(git -C "$wt" status --porcelain --untracked-files=normal)"; then
            echo "  refused: git status failed" >&2
            return 1
        fi
        if [[ -n "$changes" ]]; then
            echo "  refused: uncommitted or untracked changes" >&2
            return 1
        fi
        # Ignored, so status doesn't show them, and other checkouts may link to them.
        material="$(signing_material "$wt" | paste -sd ' ' -)"
        if [[ -n "$material" ]]; then
            echo "  refused: holds signing material — move it first: $material" >&2
            return 1
        fi
    fi
    (( FORCE )) && return 0
    # By ref, so a tag of the same name can't answer for the branch.
    tip="${WT_HEAD}"
    [[ -n "$WT_BRANCH" ]] && tip="refs/heads/$WT_BRANCH"
    [[ -n "$tip" ]] || return 0
    for base in "${BASES[@]}"; do
        git_main show-ref --verify -q "refs/heads/$base" && base="refs/heads/$base"
        git_main rev-parse --verify -q "$base^{commit}" >/dev/null || continue
        git_main merge-base --is-ancestor "$tip" "$base" && return 0
    done
    echo "  refused: ${WT_BRANCH:-$WT_HEAD} is not merged into ${BASES[*]} (--force to drop it)" >&2
    return 1
}

remove_worktree() {
    local wt="$1" kb
    (( WT_REGISTERED )) || return 0
    # Also unregisters one whose directory is already gone.
    kb="$(size_kb "$wt")"
    TOTAL_KB=$(( TOTAL_KB + kb ))
    if (( DRY_RUN )); then
        echo "  would remove worktree $wt ($(human "$kb"))"
    elif git_main worktree remove "$wt"; then
        echo "  removed worktree $wt ($(human "$kb"))"
        if [[ -n "$FA_CLEANUP_CALLER_DIR" && "$FA_CLEANUP_CALLER_DIR/" == "$wt/"* ]]; then
            CALLER_REMOVED=1
        fi
    else
        TOTAL_KB=$(( TOTAL_KB - kb ))
        echo "  could not remove worktree $wt, so left everything else in place" >&2
        return 1
    fi
}

delete_branch() {
    if [[ -n "$WT_BRANCH" ]]; then
        # -D: -d checks against the current HEAD, and the gate already checked the bases.
        if (( DRY_RUN )); then
            echo "  would delete branch $WT_BRANCH"
        elif git_main branch -D "$WT_BRANCH" >/dev/null; then
            echo "  deleted branch $WT_BRANCH"
        else
            warn "could not delete branch $WT_BRANCH"; FAILED=1
        fi
    fi
}

clean_worktree() {
    local wt="$1" name
    name="$(basename "$wt")"
    echo "$name ($wt)"

    if [[ "$wt" == "$MAIN" ]]; then
        echo "  refused: that is the main checkout" >&2
        return 1
    fi

    read_worktree "$wt"
    if [[ -d "$wt" ]] && (( ! WT_REGISTERED )); then
        echo "  refused: not a worktree of $MAIN" >&2
        return 1
    fi
    # Its app and simulator are keyed by the name alone, so they are that one's too.
    if [[ -n "$WT_NAMESAKE" ]]; then
        echo "  refused: $WT_NAMESAKE shares its name" >&2
        return 1
    fi
    if (( WT_LOCKED )); then
        echo "  refused: locked (git worktree unlock $wt)" >&2
        return 1
    fi
    # A worktree removed by hand still leaves its branch behind under its name.
    if (( ! WT_REGISTERED )) && git_main show-ref --verify -q "refs/heads/$name"; then
        WT_BRANCH="$name"
    fi
    if (( ! WT_REGISTERED )) && [[ -z "$WT_BRANCH" ]]; then
        echo "  refused: neither a worktree nor a branch (--orphans sweeps what is left)" >&2
        return 1
    fi
    if [[ -n "$WT_BRANCH" ]] && contains "$WT_BRANCH" "${BASES[@]}" "${PROTECTED[@]}"; then
        echo "  refused: $WT_BRANCH is a base branch" >&2
        return 1
    fi
    if ! gate "$wt"; then
        return 1
    fi

    # The worktree goes first, so a removal git refuses leaves everything else
    # in place; the Skip.env prefixes are read while it is still there.
    load_emulator
    remove_worktree "$wt" || return 1
    clean_emulator_app
    clean_simulator "$name"
    clean_derived_data "$wt"
    clean_mcp_workspaces "$wt"
    clean_slot_tokens "$wt"
    delete_branch
}

# --- orphans ----------------------------------------------------------------

KEPT=()

# The per-branch usage table: USAGE[row * 5 + column], a row per LIVE
# checkout plus a last one for what belongs to none, a column per kind.
USAGE=()
USAGE_COLUMNS=(emulator simulator DerivedData XcodeBuildMCP worktree)
EMULATOR_COL=0 SIMULATOR_COL=1 DERIVED_DATA_COL=2 MCP_COL=3 WORKTREE_COL=4

charge() {
    local cell=$(( $1 * 5 + $2 ))
    USAGE[cell]=$(( ${USAGE[cell]:-0} + $3 ))
}

row_kb() {
    local col kb=0
    for col in 0 1 2 3 4; do kb=$(( kb + ${USAGE[$1 * 5 + col]:-0} )); done
    echo "$kb"
}

# keep <column> <owner> <label> <reason> <path | app:id>: records an item the
# sweep left alone, sized, and charges it to the live checkout its owner path
# lies in, if any.
keep() {
    local col="$1" owner="$2" label="$3" reason="$4" sizing="$5" kb size row
    if [[ "$sizing" == app:* ]]; then
        app_size "${sizing#app:}"
        kb="$APP_KB" size="$APP_SIZE"
    else
        kb="$(size_kb "$sizing")" size="$(human "$kb")"
    fi
    row="$(live_index "$owner")" || row=${#LIVE[@]}
    charge "$row" "$col" "$kb"
    KEPT+=("  kept $label ($size) — $reason")
}

# Ends a section: what was kept, after what was removed.
end_section() {
    (( $1 )) || echo "  nothing to remove"
    local line
    for line in "${KEPT[@]}"; do echo "$line"; done
    KEPT=()
}

# Index of $1 among the other arguments.
index_of() {
    local needle="$1" i=0 x
    shift
    for x in "$@"; do
        [[ "$x" == "$needle" ]] && { echo "$i"; return 0; }
        i=$(( i + 1 ))
    done
    return 1
}

# Index of the LIVE checkout a path lies in.
live_index() {
    local i
    [[ -n "$1" ]] || return 1
    for i in "${!LIVE[@]}"; do
        if [[ "$1" == "${LIVE[$i]}" || "$1" == "${LIVE[$i]}/"* ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

# The path a kept item belongs to, and whether its worktree is merged and
# clean, so that it is kept only for want of a cleanup-worktree.sh run.
user_of() {
    local i
    if i="$(live_index "$1")"; then
        echo "$(tilde "$1")${LIVE_NOTES[$i]}"
    else
        tilde "$1"
    fi
}

# usage_line <width> <label> <kb>…: the label, a size (or -) per kb, and their total.
usage_line() {
    local width="$1" label="$2" kb total=0
    shift 2
    printf '  %-*s' "$width" "$label"
    for kb in "$@"; do
        total=$(( total + kb ))
        if (( kb )); then printf ' %13s' "$(human "$kb")"; else printf ' %13s' -; fi
    done
    printf ' %13s\n' "$(human "$total")"
}

# What each live checkout's branch costs, all kinds together, largest first,
# then each kind's total.
report_usage() {
    local i col label width=6 labels=() cells sums=()
    for (( i = 0; i <= ${#LIVE[@]}; i++ )); do
        label="${LIVE_BRANCHES[$i]:-other (in no worktree)}"
        labels+=("$label")
        (( ${#label} > width )) && width=${#label}
    done
    for col in 0 1 2 3 4; do
        sums[col]=0
        for (( i = 0; i <= ${#LIVE[@]}; i++ )); do
            sums[col]=$(( sums[col] + ${USAGE[i * 5 + col]:-0} ))
        done
    done

    echo "Storage per branch"
    printf '  %-*s' "$width" branch
    for col in "${USAGE_COLUMNS[@]}" total; do printf ' %13s' "$col"; done
    echo
    for (( i = 0; i <= ${#LIVE[@]}; i++ )); do
        cells=()
        for col in 0 1 2 3 4; do cells+=("${USAGE[i * 5 + col]:-0}"); done
        printf '%s\t%s\n' "$(row_kb "$i")" "$(usage_line "$width" "${labels[$i]}" "${cells[@]}")"
    done | sort -rn | cut -f2-
    usage_line "$width" all "${sums[@]}"
}

tilde() {
    # shellcheck disable=SC2088 # a literal ~, for display
    if [[ "$1" == "$HOME/"* ]]; then echo "~/${1#"$HOME/"}"; else echo "$1"; fi
}

clean_orphans() {
    local live=() live_names=() live_suffixes=() live_hashes=() live_hash_paths=()
    local live_mcp_keys=() live_mcp_paths=() dead_names=() dead_hashes=() candidates=()
    local wt name dir path key id prefix suffix line udid state sim found i tmp

    # Porcelain blocks end with a blank line.
    LIVE_BRANCHES=()
    wt="" name=""
    while IFS= read -r line; do
        case "$line" in
            "worktree "*) wt="${line#worktree }" ;;
            "branch "*)   name="${line#branch refs/heads/}" ;;
            "")           if [[ -d "$wt" ]]; then
                              live+=("$wt")
                              LIVE_BRANCHES+=("${name:-(detached) $(basename "$wt")}")
                          fi
                          wt="" name="" ;;
        esac
    done < <(git_main worktree list --porcelain; echo)
    for wt in "${live[@]}"; do live_names+=("$(basename "$wt")"); done

    # A live worktree the gate would let go (read_worktree reuses KEYS).
    LIVE=("${live[@]}") LIVE_NOTES=()
    for wt in "${live[@]}"; do
        name=""
        if [[ "$wt" != "$MAIN" ]]; then
            read_worktree "$wt"
            if (( ! WT_LOCKED )) && [[ -z "$WT_NAMESAKE" ]] \
                && { [[ -z "$WT_BRANCH" ]] || ! contains "$WT_BRANCH" "${BASES[@]}" "${PROTECTED[@]}"; } \
                && gate "$wt" 2>/dev/null; then
                name=" — merged and clean"
            fi
        fi
        LIVE_NOTES+=("$name")
    done
    compute_keys suffix "$(printf '%s\n' "${live[@]}")"
    live_suffixes=("${KEYS[@]}")
    compute_keys dd "$(for wt in "${live[@]}"; do derived_data_paths "$wt"; done)"
    live_hashes=("${KEYS[@]}") live_hash_paths=("${KEY_PATHS[@]}")
    compute_keys mcp "$(for wt in "${live[@]}"; do mcp_roots "$wt"; done)"
    live_mcp_keys=("${KEYS[@]}") live_mcp_paths=("${KEY_PATHS[@]}")

    # Names a removed worktree may have had: its simulator's, its branch's and
    # its XcodeBuildMCP workspace's.
    load_simulators
    for line in "${SIMS[@]}"; do dead_names+=("${line##*|}"); done
    while IFS= read -r name; do dead_names+=("$name"); done \
        < <(git_main for-each-ref --format='%(refname:short)' refs/heads)
    for dir in "$MCP_WORKSPACES"/*-*; do
        [[ -d "$dir" ]] && key="$(basename "$dir")" && dead_names+=("${key%-*}")
    done
    for name in "${dead_names[@]}"; do
        [[ -n "$name" && ! -e "$WORKTREES/$name" ]] || continue
        contains "$WORKTREES/$name" "${candidates[@]}" || candidates+=("$WORKTREES/$name")
    done
    compute_keys dd "$(for wt in "${candidates[@]}"; do derived_data_paths "$wt"; done)"
    dead_hashes=("${KEYS[@]}")

    # Buffered to files so the "merged and clean" summary below — which needs
    # every section's charges tallied first — can still print before them.
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/fa-orphans.XXXXXX")"
    exec 5>&1

    exec 1>"$tmp/emulator"
    echo "Emulator apps"
    load_emulator
    found=0
    if [[ "$EMULATOR" == down ]]; then
        warn "no booted emulator (or several, without ANDROID_SERIAL) — its apps are not swept"
    else
        for id in "${PACKAGES[@]}"; do
            for prefix in "${PREFIXES[@]}"; do
                if [[ "$id" == "$prefix" ]]; then
                    keep $EMULATOR_COL "" "$id" "the unsuffixed (release or distribution) build" "app:$id"
                    break
                fi
                suffix="${id#"$prefix".}"
                [[ "$suffix" != "$id" ]] || continue
                if [[ "$suffix" == test ]]; then
                    keep $EMULATOR_COL "" "$id" "the unsuffixed build's test APK" "app:$id"
                elif [[ ! "$suffix" =~ ^[A-Za-z0-9_]+(\.test)?$ ]]; then
                    keep $EMULATOR_COL "" "$id" "not a worktree's app id" "app:$id"
                elif i="$(index_of "${suffix%.test}" "${live_suffixes[@]}")"; then
                    keep $EMULATOR_COL "${live[$i]}" "$id" "$(user_of "${live[$i]}")" "app:$id"
                else
                    uninstall_app "$id"
                    found=1
                fi
                break
            done
        done
    fi
    end_section "$found"
    exec 1>&5

    exec 1>"$tmp/simulators"
    echo "Simulators"
    found=0
    for line in "${SIMS[@]}"; do
        IFS='|' read -r udid state sim <<< "$line"
        if i="$(index_of "$sim" "${live_names[@]}")"; then
            keep $SIMULATOR_COL "${live[$i]}" "FA $sim" "$(user_of "${live[$i]}")" "$SIM_DEVICES/$udid"
        else
            remove_simulator "$udid" "$state" "$sim"
            found=1
        fi
    done
    end_section "$found"
    exec 1>&5

    exec 1>"$tmp/derived_data"
    echo "DerivedData"
    found=0
    # By the hash of a removed worktree we know the name of; failing that, by
    # name prefix for those without an info.plist (Skip's never have one) — not
    # Project-*, which every Skip app's workspace makes — and by the recorded
    # path for any other that was under $WORKTREES.
    for dir in "$DERIVED_DATA"/*-*; do
        [[ -d "$dir" && "${dir##*-}" =~ ^[a-z]{28}$ ]] || continue
        name="$(basename "$dir")"
        if i="$(index_of "${dir##*-}" "${live_hashes[@]}")"; then
            keep $DERIVED_DATA_COL "${live_hash_paths[$i]}" "$name" "$(user_of "${live_hash_paths[$i]}")" "$dir"
            continue
        fi
        if ! contains "${dir##*-}" "${dead_hashes[@]}"; then
            path="$(workspace_path "$dir")"
            if [[ -n "$path" && -e "$path" ]]; then
                keep $DERIVED_DATA_COL "$path" "$name" "$(user_of "$path")" "$dir"
                continue
            elif [[ -n "$path" && "$path" != "$WORKTREES/"* ]]; then
                keep $DERIVED_DATA_COL "" "$name" "$(tilde "$path"), gone, but not under $(tilde "$WORKTREES")" "$dir"
                continue
            elif [[ -z "$path" ]]; then
                case "$name" in
                    FurAffinity-*|FurAffinityUI-*|FAKit-*|FALogging-*) ;;
                    *) keep $DERIVED_DATA_COL "" "$name" "no info.plist, and not one of this repo's project names" "$dir"
                       continue ;;
                esac
            fi
        fi
        remove_tree "$dir" "DerivedData/$name"
        found=1
    done
    end_section "$found"
    exec 1>&5

    # A workspace key is <basename>-<sha256[:12]> of its root, so a removed
    # worktree's is recomputable, at its root or in a subdir, as long as its
    # name survives somewhere: a subdir's key alone doesn't carry it.
    exec 1>"$tmp/mcp"
    echo "XcodeBuildMCP workspaces"
    found=0
    compute_keys mcp "$(for wt in "${candidates[@]}"; do mcp_roots "$wt"; done)"
    for dir in "$MCP_WORKSPACES"/*-*; do
        [[ -d "$dir" ]] || continue
        key="$(basename "$dir")"
        if i="$(index_of "$key" "${KEYS[@]}")"; then
            remove_tree "$dir" "XcodeBuildMCP workspace $key ($(tilde "${KEY_PATHS[$i]}"))"
            found=1
        elif i="$(index_of "$key" "${live_mcp_keys[@]}")"; then
            keep $MCP_COL "${live_mcp_paths[$i]}" "$key" "$(user_of "${live_mcp_paths[$i]}")" "$dir"
        else
            keep $MCP_COL "" "$key" "started outside $(tilde "$WORKTREES"), or in a removed worktree whose name is lost" "$dir"
        fi
    done
    end_section "$found"
    exec 1>&5
    exec 5>&-

    for i in "${!LIVE[@]}"; do charge "$i" $WORKTREE_COL "$(size_kb "${LIVE[$i]}")"; done

    # Not leftovers, since they still exist, but the next thing to reclaim —
    # surfaced first since it's easy to miss buried after the sections below.
    echo "Merged and clean worktrees — safe to remove with cleanup-worktree.sh <name>:"
    found=0
    for i in "${!LIVE[@]}"; do
        [[ -n "${LIVE_NOTES[$i]}" ]] || continue
        echo "  $(basename "${LIVE[$i]}") ($(human "$(row_kb "$i")")) — $(tilde "${LIVE[$i]}")"
        found=1
    done
    (( found )) || echo "  none"

    cat "$tmp/emulator" "$tmp/simulators" "$tmp/derived_data" "$tmp/mcp"
    rm -rf "$tmp"
    report_slots
    report_legacy_build

    report_usage
}

# --- run --------------------------------------------------------------------

status=0
if (( ORPHANS )); then
    clean_orphans
else
    for t in "${TARGETS[@]}"; do
        clean_worktree "$(target_path "$t")" || status=1
    done
fi

if (( DRY_RUN )); then
    echo "would reclaim $(human "$TOTAL_KB")"
else
    echo "reclaimed $(human "$TOTAL_KB")"
fi

if (( CALLER_REMOVED )); then
    echo "note: your shell is in a deleted directory — cd $MAIN"
fi

(( FAILED )) && status=1
exit $status
