#!/bin/bash
#
# Remove a merged worktree and everything it left behind outside its directory.
#
# `git worktree remove` takes the worktree's own .build/ and Gradle output, but
# not what is keyed by its path or name elsewhere: its emulator debug app, its
# `FA <name>` simulator, its DerivedData dirs (the Skip Xcode project's have no
# info.plist, so nothing can tell whose they are but the path hash) and its
# XcodeBuildMCP workspace. This removes all of them, then the worktree and its
# branch.
#
# Usage: Scripts/cleanup-worktree.sh [--dry-run] [--force] [--base <branch>]… <worktree name|path>…
#        Scripts/cleanup-worktree.sh [--dry-run] --orphans
#
#   --dry-run   print what would be removed, and its size, without removing it
#   --force     skip the gate: remove a dirty or unmerged worktree and branch
#   --base      a branch the worktree's must be merged into; repeatable,
#               replaces the default `android` and `main`
#   --orphans   sweep what worktrees removed without this script left behind
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
# (which device, when several are attached).

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }

ROOT="${FA_CLEANUP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"

DRY_RUN=0
FORCE=0
ORPHANS=0
BASES=()
TARGETS=()

while (( $# )); do
    case "$1" in
        -h|--help)   sed -n '3,30p' "$0" | cut -c3-; exit 0 ;;
        --dry-run)   DRY_RUN=1 ;;
        --force)     FORCE=1 ;;
        --orphans)   ORPHANS=1 ;;
        --base)      [[ -n "$2" ]] || die "--base takes a branch"; BASES+=("$2"); shift ;;
        --base=*)    BASES+=("${1#*=}") ;;
        --)          shift; TARGETS+=("$@"); break ;;
        -*)          die "unknown option $1 (see --help)" ;;
        *)           TARGETS+=("$1") ;;
    esac
    shift
done

(( ${#BASES[@]} )) || BASES=(android main)

if (( ORPHANS )); then
    (( ${#TARGETS[@]} == 0 )) || die "--orphans takes no worktree"
else
    (( ${#TARGETS[@]} )) || die "no worktree given (see --help)"
fi

# --- where things are -------------------------------------------------------

COMMON="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)" \
    || die "$ROOT is not in a git repository"
MAIN="$(cd "$(dirname "$COMMON")" && pwd -P)"
WORKTREES="$(dirname "$MAIN")/FurAffinity-worktrees"

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
MCP_WORKSPACES="$HOME/Library/Developer/XcodeBuildMCP/workspaces"
SIM_DEVICES="$HOME/Library/Developer/CoreSimulator/Devices"

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
        caller_inside=0
        for wt in "${RESOLVED[@]}"; do [[ "$HERE/" == "$wt/"* ]] && caller_inside=1; done
        cd "$MAIN"
        FA_CLEANUP_REEXEC="$TMP" FA_CLEANUP_ROOT="$MAIN" FA_CLEANUP_LOCK="$TMP/with-emulator-lock.sh" \
            FA_CLEANUP_CALLER_INSIDE="$caller_inside" \
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
    else:
        slug = re.sub(r"[^A-Za-z0-9._-]+", "-", os.path.basename(p) or "workspace")
        slug = re.sub(r"^[.-]+|[.-]+$", "", slug)[:64] or "workspace"
        out = slug + "-" + hashlib.sha256(p.encode()).hexdigest()[:12]
    print(out, p)
'
path_keys() { python3 -c "$PATH_KEYS_PY" "$1"; }

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
        warn "could not remove all of $label"
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

# applicationIdSuffix, as Android/app/build.gradle.kts derives it.
app_suffix() { local s="$1"; echo "${s//[^A-Za-z0-9_]/_}"; }

EMULATOR=unknown
PACKAGES=()
PREFIXES=()

load_emulator() {
    [[ "$EMULATOR" == unknown ]] || return 0
    local p
    while IFS= read -r p; do [[ -n "$p" ]] && PREFIXES+=("$p"); done < <(app_prefixes)
    if [[ -x "$ADB" && "$("$ADB" get-state 2>/dev/null | tr -d '\r')" == device ]]; then
        EMULATOR=up
        while IFS= read -r p; do PACKAGES+=("$p"); done \
            < <("$ADB" shell pm list packages 2>/dev/null | tr -d '\r' | sed -n 's/^package://p')
    else
        EMULATOR=down
    fi
}

uninstall_app() {
    local id="$1"
    if (( DRY_RUN )); then
        echo "  would uninstall $id"
        return
    fi
    local lock=()
    if [[ -x "$LOCK_SCRIPT" ]]; then
        lock=("$LOCK_SCRIPT")
    else
        warn "no $LOCK_SCRIPT — uninstalling without the emulator lock"
    fi
    if "${lock[@]}" "$ADB" uninstall "$id" >/dev/null; then
        echo "  uninstalled $id"
    else
        warn "could not uninstall $id"
    fi
}

clean_emulator_app() {
    local name="$1" suffix prefix id found=0
    load_emulator
    suffix="$(app_suffix "$name")"
    if [[ "$EMULATOR" == down ]]; then
        for prefix in "${PREFIXES[@]}"; do
            warn "no emulator — later: adb uninstall $prefix.$suffix"
        done
        return
    fi
    for prefix in "${PREFIXES[@]}"; do
        id="$prefix.$suffix"
        if contains "$id" "${PACKAGES[@]}"; then
            uninstall_app "$id"
            found=1
        fi
    done
    (( found )) || echo "  no emulator app"
}

# --- the simulator ----------------------------------------------------------

# "<udid>|<state>|<name>" for every `FA <name>` device.
fa_simulators() {
    xcrun simctl list devices 2>/dev/null \
        | sed -nE 's@^[[:space:]]*FA (.+) \(([0-9A-Fa-f-]{36})\) \(([A-Za-z ]+)\).*@\2|\3|\1@p'
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
        warn "could not delete simulator FA $name"
    fi
}

clean_simulator() {
    local name="$1" udid state sim found=0
    # Matching the whole name is what keeps `FA android` from also taking
    # `FA android-ci`.
    while IFS='|' read -r udid state sim; do
        if [[ "$sim" == "$name" ]]; then
            remove_simulator "$udid" "$state" "$sim"
            found=1
        fi
    done < <(fa_simulators)
    (( found )) || echo "  no simulator"
}

# --- DerivedData and XcodeBuildMCP -----------------------------------------

workspace_path() { plutil -extract WorkspacePath raw -o - "$1/info.plist" 2>/dev/null || true; }

clean_derived_data() {
    local wt="$1" hash dir path found=0 hashes=()
    while read -r hash _; do hashes+=("$hash"); done < <(derived_data_paths "$wt" | path_keys dd)
    for dir in "$DERIVED_DATA"/*-*; do
        [[ -d "$dir" ]] || continue
        path="$(workspace_path "$dir")"
        if contains "${dir##*-}" "${hashes[@]}" || [[ -n "$path" && "$path/" == "$wt/"* ]]; then
            remove_tree "$dir" "DerivedData/$(basename "$dir")"
            found=1
        fi
    done
    (( found )) || echo "  no DerivedData"
}

clean_mcp_workspaces() {
    local wt="$1" key found=0
    while read -r key _; do
        if [[ -d "$MCP_WORKSPACES/$key" ]]; then
            remove_tree "$MCP_WORKSPACES/$key" "XcodeBuildMCP workspace $key"
            found=1
        fi
    done < <(mcp_roots "$wt" | path_keys mcp)
    (( found )) || echo "  no XcodeBuildMCP workspace"
}

# --- one worktree -----------------------------------------------------------

# Sets WT_REGISTERED, WT_LOCKED, WT_BRANCH and WT_HEAD from `git worktree list`,
# and WT_NAMESAKE to another live checkout whose name gives the same app id.
read_worktree() {
    local wt="$1" line cur=""
    WT_REGISTERED=0 WT_LOCKED=0 WT_BRANCH="" WT_HEAD="" WT_NAMESAKE=""
    while IFS= read -r line; do
        case "$line" in
            "worktree "*) cur="${line#worktree }"
                          [[ "$cur" != "$wt" && -d "$cur" \
                              && "$(app_suffix "$(basename "$cur")")" == "$(app_suffix "$(basename "$wt")")" ]] \
                              && WT_NAMESAKE="$cur" ;;
            "HEAD "*)     [[ "$cur" == "$wt" ]] && WT_HEAD="${line#HEAD }" ;;
            "branch "*)   [[ "$cur" == "$wt" ]] && WT_BRANCH="${line#branch refs/heads/}" ;;
            locked*)      [[ "$cur" == "$wt" ]] && WT_LOCKED=1 ;;
        esac
        [[ "$cur" == "$wt" ]] && WT_REGISTERED=1
    done < <(git_main worktree list --porcelain)
    return 0
}

# Refuses (non-zero) when removing the worktree would lose work.
gate() {
    local wt="$1" tip base
    local changes
    if [[ -d "$wt" ]] && (( WT_REGISTERED )); then
        if ! changes="$(git -C "$wt" status --porcelain --untracked-files=normal)"; then
            echo "  refused: git status failed" >&2
            return 1
        fi
        if [[ -n "$changes" ]]; then
            echo "  refused: uncommitted or untracked changes (--force to discard them)" >&2
            return 1
        fi
    fi
    tip="${WT_BRANCH:-$WT_HEAD}"
    [[ -n "$tip" ]] || return 0
    for base in "${BASES[@]}"; do
        git_main rev-parse --verify -q "$base^{commit}" >/dev/null || continue
        git_main merge-base --is-ancestor "$tip" "$base" && return 0
    done
    echo "  refused: $tip is not merged into ${BASES[*]} (--force to drop it)" >&2
    return 1
}

remove_worktree() {
    local wt="$1" kb flags=()
    (( WT_REGISTERED )) || return 0
    (( FORCE )) && flags+=(--force)
    # Also unregisters one whose directory is already gone.
    kb="$(size_kb "$wt")"
    TOTAL_KB=$(( TOTAL_KB + kb ))
    if (( DRY_RUN )); then
        echo "  would remove worktree $wt ($(human "$kb"))"
    elif git_main worktree remove "${flags[@]}" "$wt"; then
        echo "  removed worktree $wt ($(human "$kb"))"
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
            warn "could not delete branch $WT_BRANCH"
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
    if [[ -n "$WT_BRANCH" ]] && contains "$WT_BRANCH" "${BASES[@]}" main android; then
        echo "  refused: $WT_BRANCH is a base branch" >&2
        return 1
    fi
    if (( ! FORCE )) && ! gate "$wt"; then
        return 1
    fi

    # The worktree goes first, so a removal git refuses leaves everything else
    # in place; the Skip.env prefixes are read while it is still there.
    load_emulator
    remove_worktree "$wt" || return 1
    clean_emulator_app "$name"
    clean_simulator "$name"
    clean_derived_data "$wt"
    clean_mcp_workspaces "$wt"
    delete_branch
}

# --- orphans ----------------------------------------------------------------

clean_orphans() {
    local live=() live_names=() live_suffixes=() live_hashes=() dead_names=()
    local wt name hash dir path key slug candidate id prefix suffix udid state sim found

    while IFS= read -r wt; do
        [[ -d "$wt" ]] && live+=("$wt")
    done < <(git_main worktree list --porcelain | sed -n 's/^worktree //p')
    for wt in "${live[@]}"; do
        name="$(basename "$wt")"
        live_names+=("$name")
        live_suffixes+=("$(app_suffix "$name")")
    done
    while read -r hash _; do live_hashes+=("$hash"); done < <(
        for wt in "${live[@]}"; do derived_data_paths "$wt"; done | path_keys dd
    )

    echo "Emulator apps"
    load_emulator
    found=0
    if [[ "$EMULATOR" == down ]]; then
        warn "no emulator — its apps are not swept"
    else
        for id in "${PACKAGES[@]}"; do
            for prefix in "${PREFIXES[@]}"; do
                suffix="${id#"$prefix".}"
                [[ "$suffix" != "$id" && "$suffix" =~ ^[A-Za-z0-9_]+$ ]] || continue
                contains "$suffix" "${live_suffixes[@]}" && continue
                uninstall_app "$id"
                found=1
            done
        done
    fi
    (( found )) || echo "  none"

    echo "Simulators"
    found=0
    while IFS='|' read -r udid state sim; do
        dead_names+=("$sim")
        contains "$sim" "${live_names[@]}" && continue
        remove_simulator "$udid" "$state" "$sim"
        found=1
    done < <(fa_simulators)
    (( found )) || echo "  none"

    echo "DerivedData"
    found=0
    # By name prefix for those without an info.plist (Skip's never have one) —
    # not Project-*, which every Skip app's workspace makes — and by the
    # recorded path for any other that was under $WORKTREES.
    for dir in "$DERIVED_DATA"/*-*; do
        [[ -d "$dir" && "${dir##*-}" =~ ^[a-z]{28}$ ]] || continue
        contains "${dir##*-}" "${live_hashes[@]}" && continue
        path="$(workspace_path "$dir")"
        if [[ -n "$path" ]]; then
            [[ "$path" == "$WORKTREES/"* && ! -e "$path" ]] || continue
        else
            case "$(basename "$dir")" in
                FurAffinity-*|FurAffinityUI-*|FAKit-*|FALogging-*) ;;
                *) continue ;;
            esac
        fi
        remove_tree "$dir" "DerivedData/$(basename "$dir")"
        found=1
    done
    (( found )) || echo "  none"

    # A workspace key is <basename>-<sha256[:12]> of its root, so a removed
    # worktree's is recomputable: from its name when it was started at the
    # root, and from any name we still know of when it was started in a subdir.
    echo "XcodeBuildMCP workspaces"
    found=0
    while IFS= read -r name; do dead_names+=("$name"); done < <(git_main for-each-ref --format='%(refname:short)' refs/heads)
    for dir in "$MCP_WORKSPACES"/*-*; do
        [[ -d "$dir" ]] || continue
        key="$(basename "$dir")"
        slug="${key%-*}"
        while read -r candidate path; do
            [[ "$candidate" == "$key" && ! -e "$path" ]] || continue
            remove_tree "$dir" "XcodeBuildMCP workspace $key ($path)"
            found=1
            break
        done < <(
            echo "$WORKTREES/$slug"
            if contains "$slug" "${SUBDIRS[@]}"; then
                for name in "${dead_names[@]}"; do echo "$WORKTREES/$name/$slug"; done
            fi | path_keys mcp
        )
    done
    (( found )) || echo "  none"
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
    echo "would reclaim $(human "$TOTAL_KB") (plus emulator app data)"
else
    echo "reclaimed $(human "$TOTAL_KB") (plus emulator app data)"
fi

if [[ "$FA_CLEANUP_CALLER_INSIDE" == 1 ]] && (( ! DRY_RUN )); then
    echo "note: your shell is in a deleted directory — cd $MAIN"
fi

exit $status
