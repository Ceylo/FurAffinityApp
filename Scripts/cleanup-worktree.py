#!/usr/bin/env python3
"""Remove a merged worktree and everything it left behind outside its directory.

`git worktree remove` takes the worktree's own .build/ and Gradle output, but
not what is keyed by its path or name elsewhere: its emulator debug app, its
`FA <name>` simulator, its DerivedData dirs (the Skip Xcode project's have no
info.plist, so nothing can tell whose they are but the path hash) and its
XcodeBuildMCP workspace. This removes the worktree first, so a removal git
refuses leaves everything else in place, then all of them, then its branch.
The Android build slots stay: any worktree reuses them.

Usage: Scripts/cleanup-worktree.py [--dry-run] [--force] [--base <branch>]… <worktree name|path>…
       Scripts/cleanup-worktree.py [--dry-run] [--reclaim] --orphans

  --dry-run   print what would be removed, and its size, without removing it
  --force     remove an unmerged worktree and branch (a squash-merged one);
              a worktree with changes is refused regardless
  --base      a branch the worktree's must be merged into; repeatable,
              replaces the default `android` and `main`
  --orphans   sweep what worktrees removed without this script left behind,
              list what it kept and what still uses it, and total the storage
              of each branch; it assumes every checkout is a worktree of this repo.
              It also reports the Android build slots, and each worktree's
              .build but its Android/ (the :app outputs) and .fa-slot* files,
              which Gradle builds in a slot don't use
  --reclaim   with --orphans, also delete that .build content, but not a
              worktree's while a build tool runs in it; `skip android build`
              and `swift package update` recreate it cold

A bare name is a directory under ../FurAffinity-worktrees. The worktree may
already be gone (ExitWorktree, `git worktree remove`): its leftovers are still
found. Run it from inside the worktree being removed if you like; your shell is
then in a deleted directory.

Shared caches (~/.gradle, SwiftPM, ModuleCache.noindex) are left alone: they
are content-addressed or self-pruning, and not any one worktree's.

Environment: ANDROID_HOME / ANDROID_SDK_ROOT (SDK location), ANDROID_SERIAL
(which device, when several are attached), FA_ANDROID_SLOTS_DIR (the build
slots' parent, default ~/Library/Developer/Xcode/DerivedData).
"""
import argparse
import atexit
import datetime
import functools
import hashlib
import locale
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "Android"))
from fa_paths import DERIVED_DATA, derived_data_hash, workspace_path  # noqa: E402
import slots  # noqa: E402

try:
    locale.setlocale(locale.LC_NUMERIC, "")
except locale.Error:
    pass

ROOT = HERE.parent
HOME = Path.home()
MCP_WORKSPACES = HOME / "Library/Developer/XcodeBuildMCP/workspaces"
SIM_DEVICES = HOME / "Library/Developer/CoreSimulator/Devices"
SLOTS_DIR = Path(os.environ.get("FA_ANDROID_SLOTS_DIR") or DERIVED_DATA)
SDK = Path(os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
           or HOME / "Library/Android/sdk")
ADB = SDK / "platform-tools/adb"
LOCK_SCRIPT = ROOT / "Scripts/Android/with-emulator-lock.sh"
ADB_STATE = ROOT / "Scripts/Android/adb-state.sh"
SIGNING_MATERIAL = ROOT / "Scripts/signing-material.sh"

# Never removed, whatever --base says.
PROTECTED = ["android", "main"]
# Subdirectories an agent may start XcodeBuildMCP in, or Xcode may open as a package.
SUBDIRS = ["FAKit", "FALogging", "Android", "Darwin", "FurAffinity"]
USAGE_COLUMNS = ["emulator", "simulator", "DerivedData", "XcodeBuildMCP", "worktree"]
EMULATOR_COL, SIMULATOR_COL, DERIVED_DATA_COL, MCP_COL, WORKTREE_COL = range(5)


# --- output -----------------------------------------------------------------

args = None
PAINT = RESET = ""
total_kb = 0
failed = False
caller_removed = False
# Set by main().
MAIN = WORKTREES = CALLER_DIR = lock_script = ""
signing_helper = str(SIGNING_MATERIAL)


def die(message):
    sys.exit(f"error: {message}")


def warn(message):
    print(f"warning: {message}", file=sys.stderr)


def fail(message):
    global failed
    warn(message)
    failed = True


def painted(message):
    """What is or would be removed: yellow on a dry run, green for real."""
    return f"{PAINT}{message}{RESET}"


def human(kb):
    if kb >= 1048576:
        return locale.format_string("%.1f GB", kb / 1048576)
    if kb >= 1024:
        return locale.format_string("%.0f MB", kb / 1024)
    return f"{kb} KB"


def tilde(path):
    path = str(path)
    return "~/" + path[len(str(HOME)) + 1:] if path.startswith(f"{HOME}/") else path


def size_kb(*paths):
    """du's size even when it fails partway (a build rewriting the tree, a missing dir)."""
    kb = 0
    for path in paths:
        out = run("du", "-sk", str(path)).stdout.split("\t", 1)[0]
        kb += int(out) if out.isdigit() else 0
    return kb


def run(*cmd, show_errors=False, **kwargs):
    """The command's result, its stdout captured, and its stderr too unless
    show_errors: what a failed removal says, or the emulator lock's wait."""
    return subprocess.run([str(c) for c in cmd], stdout=subprocess.PIPE,
                          stderr=None if show_errors else subprocess.PIPE, text=True, **kwargs)


def git(repo, *cmd):
    return run("git", "-C", repo, *cmd)


def git_main(*cmd, **kwargs):
    return run("git", "-C", MAIN, *cmd, **kwargs)


def reclaim(kb, would, did, out, action):
    """Count kb as reclaimed and report it: on a dry run only `would`, else `did`
    once action() — which reports its own failure — has succeeded."""
    global total_kb
    if not args.dry_run and not action():
        return False
    total_kb += kb
    out.append(painted(f"  {would if args.dry_run else did}"))
    return True


def rm_rf(paths):
    """Like rm -rf, retried: Finder writes a .DS_Store into a folder it shows
    while it is emptied. The paths it could not remove."""
    for attempt in range(3):
        if attempt:
            time.sleep(1)
        errors = []

        def record(_, failed_path, exc_info):
            if not isinstance(exc_info[1], FileNotFoundError):
                errors.append(failed_path)

        for path in paths:
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path, onerror=record)
            else:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass
                except OSError:
                    errors.append(path)
        if not errors:
            break
    return errors


def remove_tree(label, paths, out, kb=None):
    """Remove file trees, reporting their size, measured unless given."""
    kb = size_kb(*paths) if kb is None else kb

    def remove():
        errors = rm_rf(paths)
        if errors:
            fail(f"could not remove all of {label} ({len(errors)} left, first {errors[0]})")
        return not errors

    size = human(kb)
    reclaim(kb, f"would remove {label} ({size})", f"removed {label} ({size})", out, remove)


# --- path keys --------------------------------------------------------------

def app_suffix(path):
    """The applicationIdSuffix Android/app/build.gradle.kts derives from the
    basename — java.util.regex, like re, replaces per code point."""
    return re.sub(r"[^A-Za-z0-9_]", "_", os.path.basename(path))


def mcp_key(path):
    """XcodeBuildMCP's workspace key (build/utils/workspace-identity.js)."""
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", os.path.basename(path) or "workspace")
    slug = re.sub(r"^[.-]+|[.-]+$", "", slug)[:64] or "workspace"
    return f"{slug}-{hashlib.sha256(str(path).encode()).hexdigest()[:12]}"


def derived_data_paths(wt):
    """The candidate paths whose hash names a worktree's DerivedData dirs."""
    return [wt, f"{wt}/FurAffinity.xcodeproj", f"{wt}/Project.xcworkspace",
            f"{wt}/Darwin/FurAffinityUI.xcodeproj", f"{wt}/FAKit", f"{wt}/FALogging"]


def mcp_roots(wt):
    """The paths XcodeBuildMCP may have been started in."""
    return [wt] + [f"{wt}/{sub}" for sub in SUBDIRS]


def under(path, root):
    return path == root or path.startswith(f"{root}/")


# --- the emulator app -------------------------------------------------------

SKIP_ENV_ID = re.compile(r"^\s*(?:ANDROID_APPLICATION_ID|PRODUCT_BUNDLE_IDENTIFIER)\s*=\s*(\S+)", re.M)


def app_prefixes():
    """Every app-id prefix a debug build may have used: each live checkout's
    Skip.env, the bases', and the distribution stash's."""
    texts = []
    for wt in worktree_paths():
        try:
            texts.append(Path(wt, "Skip.env").read_text())
        except OSError:
            pass  # main has no Skip.env
    refs = list(args.base)
    stash = git_main("stash", "list", "--format=%H %gs").stdout
    refs += [m[1] for m in re.finditer(r"^(\S+) .*For App Store distribution$", stash, re.M)][:1]
    for ref in refs:
        texts.append(git_main("show", f"{ref}:Skip.env").stdout)
    return sorted({m[1] for text in texts for m in SKIP_ENV_ID.finditer(text)})


class Emulator:
    def __init__(self):
        self.prefixes = app_prefixes()
        self.packages = []
        self.up = os.access(ADB, os.X_OK) and adb_state() == "device" \
            and run(ADB, "shell", "getprop", "sys.boot_completed").stdout.strip() == "1"
        if self.up:
            out = run(ADB, "shell", "pm", "list", "packages").stdout
            self.packages = [line.strip()[len("package:"):] for line in out.splitlines()
                             if line.startswith("package:")]


@functools.cache
def emulator():
    return Emulator()


def adb_state():
    """`adb get-state`'s answer, waiting out the `offline` a fresh adb server
    reports at first: Scripts/Android/adb-state.sh's, which the other scripts source."""
    return run("bash", "-c", 'ADB="$1"; source "$2"; adb_state', "_", ADB, ADB_STATE).stdout.strip()


def app_size(app_id):
    """An installed app's APK plus data, and that for display. Its data is only
    readable through run-as, so a debug build's."""
    out = run(ADB, "shell", f"""d=$(pm path '{app_id}' | sed -n '1s/^package://p');
        du -sk "${{d%/*}}" 2>/dev/null | cut -f1 | tr '\\n' ' ';
        run-as '{app_id}' du -sk . 2>/dev/null | cut -f1""").stdout.replace("\r", "").split()
    apk, data = (int(x) if x.isdigit() else 0 for x in (out + ["", ""])[:2])
    kb = apk + data
    return kb, human(kb) if len(out) > 1 else f"{human(kb)} APK, data unreadable"


def uninstall_app(app_id, out):
    kb, size = app_size(app_id)

    def uninstall():
        lock = [lock_script] if lock_script else []
        if not lock:
            warn(f"no {LOCK_SCRIPT} — uninstalling without the emulator lock")
        if run(*lock, ADB, "uninstall", app_id, show_errors=True).returncode:
            fail(f"could not uninstall {app_id}")
            return False
        return True

    reclaim(kb, f"would uninstall {app_id} ({size})", f"uninstalled {app_id} ({size})", out, uninstall)


def clean_emulator_app(suffix, out):
    """The app and, if on-device tests ran, its instrumentation APK."""
    emu = emulator()
    if not emu.up:
        for prefix in emu.prefixes:
            warn("no booted emulator (or several, without ANDROID_SERIAL)"
                 f" — later: adb uninstall {prefix}.{suffix}")
        return
    found = False
    for prefix in emu.prefixes:
        for app_id in (f"{prefix}.{suffix}", f"{prefix}.{suffix}.test"):
            if app_id in emu.packages:
                uninstall_app(app_id, out)
                found = True
    if not found:
        out.append("  no emulator app")


# --- the simulator ----------------------------------------------------------

@functools.cache
def simulators():
    """(udid, state, name) for every `FA <name>` device, listed once (simctl
    takes ~0.3 s) — a run only ever deletes devices it has listed."""
    listing = run("xcrun", "simctl", "list", "devices").stdout
    return [(m[2], m[3], m[1]) for m in re.finditer(
        r"^\s*FA (.+) \(([0-9A-Fa-f-]{36})\) \(([A-Za-z ]+)\)", listing, re.M)]


def remove_simulator(udid, state, name, out):
    kb = size_kb(SIM_DEVICES / udid)

    def delete():
        if state != "Shutdown":
            run("xcrun", "simctl", "shutdown", udid)
        if run("xcrun", "simctl", "delete", udid, show_errors=True).returncode:
            fail(f"could not delete simulator FA {name}")
            return False
        return True

    size = human(kb)
    reclaim(kb, f"would delete simulator FA {name} ({size})", f"deleted simulator FA {name} ({size})",
            out, delete)


def clean_simulator(name, out):
    # Matching the whole name is what keeps `FA android` from also taking
    # `FA android-ci`.
    found = False
    for udid, state, sim in simulators():
        if sim == name:
            remove_simulator(udid, state, sim, out)
            found = True
    if not found:
        out.append("  no simulator")


# --- DerivedData and XcodeBuildMCP -----------------------------------------

def derived_data_dirs():
    return sorted(d for d in DERIVED_DATA.glob("*-*") if d.is_dir())


def clean_derived_data(wt, out):
    keys = {derived_data_hash(p) for p in derived_data_paths(wt)}
    found = False
    for d in derived_data_dirs():
        if d.name.startswith("android-slot-"):
            continue
        path = workspace_path(d)
        if d.name.rsplit("-", 1)[1] in keys or (path and under(path, wt)):
            remove_tree(f"DerivedData/{d.name}", [d], out)
            found = True
    if not found:
        out.append("  no DerivedData")


def clean_mcp_workspaces(wt, out):
    found = False
    for key in map(mcp_key, mcp_roots(wt)):
        if (MCP_WORKSPACES / key).is_dir():
            remove_tree(f"XcodeBuildMCP workspace {key}", [MCP_WORKSPACES / key], out)
            found = True
    if not found:
        out.append("  no XcodeBuildMCP workspace")


# --- one worktree -----------------------------------------------------------

@functools.cache
def worktree_blocks():
    """`git worktree list --porcelain`, a dict per worktree; cleared by a removal."""
    blocks = []
    for block in git_main("worktree", "list", "--porcelain").stdout.split("\n\n"):
        info = {}
        for line in block.splitlines():
            key, _, value = line.partition(" ")
            info[key] = value
        if "worktree" in info:
            blocks.append(info)
    return blocks


def worktree_paths():
    return [b["worktree"] for b in worktree_blocks()]


class Worktree:
    """What `git worktree list` says of a path, its app id suffix, and another
    live checkout whose name gives the same one."""

    def __init__(self, path):
        self.path = path
        self.name = os.path.basename(path)
        self.suffix = app_suffix(path)
        self.registered = self.locked = False
        self.branch = self.head = self.namesake = ""
        for b in worktree_blocks():
            if b["worktree"] == path:
                self.registered = True
                self.locked = "locked" in b
                self.head = b.get("HEAD", "")
                self.branch = b.get("branch", "").removeprefix("refs/heads/")
            elif os.path.isdir(b["worktree"]) and app_suffix(b["worktree"]) == self.suffix:
                self.namesake = b["worktree"]


def signing_material(wt):
    """Ignored files that must not go with the worktree — real files, not the
    links to another copy. Scripts/signing-material.sh says which, for
    slot-sync.sh too."""
    ignored = git(wt, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory").stdout
    p = run("bash", "-c", 'source "$1" || exit 2; while IFS= read -r f; do'
            ' if is_signing_material "$f"; then echo "$f"; fi; done',
            "_", signing_helper, input=ignored)
    if p.returncode:
        die(f"could not read {signing_helper}: {p.stderr.strip()}")
    matched = p.stdout
    return [f for f in matched.splitlines() if not os.path.islink(os.path.join(wt, f))]


def refusal(w):
    """Why the worktree must stay, or None; --force waives only the merge check."""
    # Its app and simulator are keyed by the name alone, so they are that one's too.
    if w.namesake:
        return f"{w.namesake} shares its name"
    if w.locked:
        return f"locked (git worktree unlock {w.path})"
    if w.branch in args.base + PROTECTED:
        return f"{w.branch} is a base branch"
    if os.path.isdir(w.path) and w.registered:
        status = git(w.path, "status", "--porcelain", "--untracked-files=normal")
        if status.returncode:
            return "git status failed"
        if status.stdout.strip():
            return "uncommitted or untracked changes"
        # Ignored, so status doesn't show them, and other checkouts may link to them.
        material = signing_material(w.path)
        if material:
            return f"holds signing material — move it first: {' '.join(material)}"
    if args.force:
        return None
    # By ref, so a tag of the same name can't answer for the branch.
    tip = f"refs/heads/{w.branch}" if w.branch else w.head
    if not tip:
        return None
    for base in args.base:
        if git_main("show-ref", "--verify", "-q", f"refs/heads/{base}").returncode == 0:
            base = f"refs/heads/{base}"
        if git_main("rev-parse", "--verify", "-q", f"{base}^{{commit}}").returncode:
            continue
        if git_main("merge-base", "--is-ancestor", tip, base).returncode == 0:
            return None
    return f"{w.branch or w.head} is not merged into {' '.join(args.base)} (--force to drop it)"


def remove_worktree(w, out):
    if not w.registered:
        return True
    # Also unregisters one whose directory is already gone.
    kb = size_kb(w.path)

    def remove():
        global caller_removed
        flush(out)
        p = git_main("worktree", "remove", w.path)
        worktree_blocks.cache_clear()
        # A .DS_Store Finder rewrites fails git partway, after it unregistered
        # the worktree: the rest is ours to remove.
        if p.returncode and (w.path in worktree_paths() or rm_rf([w.path])):
            print(p.stderr.rstrip(), file=sys.stderr)
            print(f"  could not remove worktree {w.path}, so left everything else in place",
                  file=sys.stderr)
            return False
        caller_removed = caller_removed or under(CALLER_DIR, w.path)
        return True

    size = human(kb)
    return reclaim(kb, f"would remove worktree {w.path} ({size})", f"removed worktree {w.path} ({size})",
                   out, remove)


def delete_branch(w, out):
    if not w.branch:
        return
    # -D: -d checks against the current HEAD, and the gate already checked the bases.
    if args.dry_run:
        out.append(painted(f"  would delete branch {w.branch}"))
    elif git_main("branch", "-D", w.branch, show_errors=True).returncode == 0:
        out.append(painted(f"  deleted branch {w.branch}"))
    else:
        fail(f"could not delete branch {w.branch}")


def flush(out):
    for line in out:
        print(line)
    out.clear()


def clean_worktree(wt):
    w = Worktree(wt)
    print(f"{w.name} ({wt})")

    def refuse(why):
        print(f"  refused: {why}", file=sys.stderr)
        return False

    if wt == MAIN:
        return refuse("that is the main checkout")
    if os.path.isdir(wt) and not w.registered:
        return refuse(f"not a worktree of {MAIN}")
    # A worktree removed by hand still leaves its branch behind under its name.
    if not w.registered and git_main("show-ref", "--verify", "-q", f"refs/heads/{w.name}").returncode == 0:
        w.branch = w.name
    if not w.registered and not w.branch:
        return refuse("neither a worktree nor a branch (--orphans sweeps what is left)")
    why = refusal(w)
    if why:
        return refuse(why)

    # The worktree goes first, so a removal git refuses leaves everything else
    # in place; the Skip.env prefixes are read while it is still there.
    emulator()
    out = []
    if not remove_worktree(w, out):
        return False
    clean_emulator_app(w.suffix, out)
    clean_simulator(w.name, out)
    clean_derived_data(wt, out)
    clean_mcp_workspaces(wt, out)
    delete_branch(w, out)
    flush(out)
    return True


# --- orphans ----------------------------------------------------------------

class Orphans:
    def __init__(self):
        # Porcelain blocks, for checkouts whose directory exists.
        self.live, self.branches = [], []
        for b in worktree_blocks():
            if os.path.isdir(b["worktree"]):
                self.live.append(b["worktree"])
                self.branches.append(b.get("branch", "").removeprefix("refs/heads/")
                                     or f"(detached) {os.path.basename(b['worktree'])}")
        self.notes = [self.note(wt) for wt in self.live]
        # A row per live checkout plus a last one for what belongs to none.
        self.usage = [[0] * len(USAGE_COLUMNS) for _ in range(len(self.live) + 1)]
        self.kept = []

    def note(self, wt):
        """Whether a live worktree is merged and clean, so that what it holds is
        kept only for want of a cleanup-worktree.py run."""
        return "" if wt == MAIN or refusal(Worktree(wt)) else " — merged and clean"

    def live_index(self, path):
        """Index of the live checkout a path lies in."""
        if path:
            for i, wt in enumerate(self.live):
                if under(path, wt):
                    return i
        return None

    def user_of(self, path):
        i = self.live_index(path)
        return tilde(path) + (self.notes[i] if i is not None else "")

    def keep(self, col, owner, label, reason, path=None, app=None):
        """Record an item the sweep left alone, sized, and charge it to the live
        checkout its owner path lies in, if any."""
        if app:
            kb, size = app_size(app)
        else:
            kb = size_kb(path)
            size = human(kb)
        i = self.live_index(owner)
        self.usage[len(self.live) if i is None else i][col] += kb
        self.kept.append(f"  kept {label} ({size}) — {reason}")

    def end_section(self, out, found):
        """What was kept, after what was removed."""
        if not found:
            out.append("  nothing to remove")
        out += self.kept
        self.kept = []

    def run(self):
        live = self.live
        # First one wins, as git lists them.
        by_name = {os.path.basename(wt): wt for wt in reversed(live)}
        by_suffix = {app_suffix(wt): wt for wt in reversed(live)}
        live_hashes = {derived_data_hash(p): p for wt in reversed(live) for p in derived_data_paths(wt)}
        live_mcp = {mcp_key(p): p for wt in reversed(live) for p in mcp_roots(wt)}

        # Names a removed worktree may have had: its simulator's, its branch's and
        # its XcodeBuildMCP workspace's.
        dead_names = [sim for _, _, sim in simulators()]
        dead_names += git_main("for-each-ref", "--format=%(refname:short)", "refs/heads").stdout.split()
        dead_names += [d.name.rsplit("-", 1)[0] for d in sorted(MCP_WORKSPACES.glob("*-*")) if d.is_dir()]
        candidates = list(dict.fromkeys(
            f"{WORKTREES}/{n}" for n in dead_names if n and not os.path.exists(f"{WORKTREES}/{n}")))
        dead_hashes = {derived_data_hash(p) for wt in candidates for p in derived_data_paths(wt)}

        # Buffered, so the "merged and clean" summary — which needs every
        # section's charges tallied first — can still print before them.
        sections = []

        out = ["Emulator apps"]
        found = False
        emu = emulator()
        if not emu.up:
            warn("no booted emulator (or several, without ANDROID_SERIAL) — its apps are not swept")
        for app_id in emu.packages:
            prefix = next((p for p in emu.prefixes if app_id == p or app_id.startswith(f"{p}.")), None)
            if prefix is None:
                continue
            suffix = app_id[len(prefix) + 1:]
            if not suffix:
                self.keep(EMULATOR_COL, "", app_id, "the unsuffixed (release or distribution) build", app=app_id)
            elif suffix == "test":
                self.keep(EMULATOR_COL, "", app_id, "the unsuffixed build's test APK", app=app_id)
            elif not re.fullmatch(r"[A-Za-z0-9_]+(\.test)?", suffix):
                self.keep(EMULATOR_COL, "", app_id, "not a worktree's app id", app=app_id)
            elif wt := by_suffix.get(suffix.removesuffix(".test")):
                self.keep(EMULATOR_COL, wt, app_id, self.user_of(wt), app=app_id)
            else:
                uninstall_app(app_id, out)
                found = True
        self.end_section(out, found)
        sections += out

        out = ["Simulators"]
        found = False
        for udid, state, sim in simulators():
            if wt := by_name.get(sim):
                self.keep(SIMULATOR_COL, wt, f"FA {sim}", self.user_of(wt), SIM_DEVICES / udid)
            else:
                remove_simulator(udid, state, sim, out)
                found = True
        self.end_section(out, found)
        sections += out

        # By the hash of a removed worktree we know the name of; failing that, by
        # name prefix for those without an info.plist (Skip's never have one) — not
        # Project-*, which every Skip app's workspace makes — and by the recorded
        # path for any other that was under WORKTREES.
        out = ["DerivedData"]
        found = False
        for d in derived_data_dirs():
            key = d.name.rsplit("-", 1)[1]
            if not re.fullmatch(r"[a-z]{28}", key):
                continue
            if key in live_hashes:
                self.keep(DERIVED_DATA_COL, live_hashes[key], d.name, self.user_of(live_hashes[key]), d)
                continue
            if key not in dead_hashes:
                path = workspace_path(d)
                if path and os.path.exists(path):
                    self.keep(DERIVED_DATA_COL, path, d.name, self.user_of(path), d)
                    continue
                if path and not path.startswith(f"{WORKTREES}/"):
                    self.keep(DERIVED_DATA_COL, "", d.name,
                              f"{tilde(path)}, gone, but not under {tilde(WORKTREES)}", d)
                    continue
                if not path and not d.name.startswith(("FurAffinity-", "FurAffinityUI-", "FAKit-", "FALogging-")):
                    self.keep(DERIVED_DATA_COL, "", d.name,
                              "no info.plist, and not one of this repo's project names", d)
                    continue
            remove_tree(f"DerivedData/{d.name}", [d], out)
            found = True
        self.end_section(out, found)
        sections += out

        # A workspace key is <basename>-<sha256[:12]> of its root, so a removed
        # worktree's is recomputable, at its root or in a subdir, as long as its
        # name survives somewhere: a subdir's key alone doesn't carry it.
        out = ["XcodeBuildMCP workspaces"]
        found = False
        dead_mcp = {mcp_key(p): p for wt in reversed(candidates) for p in mcp_roots(wt)}
        for d in sorted(MCP_WORKSPACES.glob("*-*")):
            if not d.is_dir():
                continue
            if d.name in dead_mcp:
                remove_tree(f"XcodeBuildMCP workspace {d.name} ({tilde(dead_mcp[d.name])})", [d], out)
                found = True
            elif d.name in live_mcp:
                self.keep(MCP_COL, live_mcp[d.name], d.name, self.user_of(live_mcp[d.name]), d)
            else:
                self.keep(MCP_COL, "", d.name,
                          f"started outside {tilde(WORKTREES)}, or in a removed worktree whose name is lost", d)
        self.end_section(out, found)
        sections += out

        for i, wt in enumerate(live):
            self.usage[i][WORKTREE_COL] += size_kb(wt)

        # Not leftovers, since they still exist, but the next thing to reclaim —
        # surfaced first since it's easy to miss buried after the sections below.
        print("Merged and clean worktrees — safe to remove with cleanup-worktree.py <name>:")
        merged = [i for i, note in enumerate(self.notes) if note]
        for i in merged:
            print(f"  {os.path.basename(live[i])} ({human(sum(self.usage[i]))}) — {tilde(live[i])}")
        if not merged:
            print("  none")

        flush(sections)
        self.report_slots()
        self.report_legacy_build()
        self.report_usage()

    def report_slots(self):
        """The slots, kept whatever their owner: any worktree reuses them, and
        FA_ANDROID_SLOTS_MAX already caps them. clean.sh --all deletes the idle ones."""
        if not SLOTS_DIR.is_dir():
            return
        try:
            rows = slots.describe(str(SLOTS_DIR))
        except OSError as e:
            fail(f"could not read the Android build slots: {e}")
            return
        out = ["Android build slots (any worktree reuses them; Scripts/Android/clean.sh --all deletes the idle ones)"]
        for path, state, owner, used in rows:
            when = "never used"
            if used.isdigit() and int(used) > 0:
                when = "last used " + datetime.datetime.fromtimestamp(int(used) / 1000).strftime("%Y-%m-%d %H:%M")
            if owner and not os.path.isdir(owner):
                owner += " (gone)"
            by = f" by {tilde(owner)}" if owner else ""
            self.kept.append(f"  kept {os.path.basename(path)} ({human(size_kb(path))}) — {state}, {when}{by}")
        self.end_section(out, False)
        flush(out)

    def report_legacy_build(self):
        """Each checkout's .build but Android/ (the :app outputs) and the .fa-slot*
        files (the slot's path, and the clean token, without which the next build
        wipes the slot). A Gradle build of a branch with build slots no longer uses
        it, but `skip android build`, `swift package update` and
        build-release-apk.sh still do, and recreate it cold. Removing only part of
        it leaves the stale state behind "missing required module" errors."""
        tools = build_tool_paths() if args.reclaim else []
        out = ["Per-worktree .build content Gradle builds in a slot don't use (all but Android/ and .fa-slot*)"]
        found = False
        for wt, branch in zip(self.live, self.branches):
            try:
                names = os.listdir(f"{wt}/.build")
            except OSError:
                continue
            names = sorted(names, key=lambda n: (n.startswith("."), n))
            entries = [f"{wt}/.build/{n}" for n in names if n != "Android" and not n.startswith(".fa-slot")]
            if not entries:
                continue
            kb = size_kb(*entries)
            label = f"{os.path.basename(wt)}/.build/{{{','.join(os.path.basename(e) for e in entries)}}}"
            # By a tracked file: ignored build output under Android/build-slots survives a checkout.
            if git(wt, "ls-files", "--error-unmatch", "--", "Android/build-slots/build.gradle.kts").returncode:
                self.kept.append(f"  kept {label} ({human(kb)}) — in use: {branch} predates build slots")
            elif args.reclaim and (tool := building_in(tools, wt, entries)):
                self.kept.append(f"  kept {label} ({human(kb)}) — {tool} is building there")
            elif args.reclaim:
                remove_tree(label, entries, out, kb=kb)
                found = True
            else:
                self.kept.append(f"  kept {label} ({human(kb)}) — not used by Gradle builds;"
                                 " `skip android build` recreates it cold (--reclaim removes it)")
        self.end_section(out, found)
        flush(out)

    def report_usage(self):
        """What each live checkout's branch costs, all kinds together, largest
        first, then each kind's total."""
        labels = self.branches + ["other (in no worktree)"]
        width = max(6, *map(len, labels))

        def line(label, cells):
            sizes = "".join(f" {human(kb) if kb else '-':>13}" for kb in cells + [sum(cells)])
            return f"  {label:<{width}}{sizes}"

        print("Storage per branch")
        print(f"  {'branch':<{width}}" + "".join(f" {c:>13}" for c in USAGE_COLUMNS + ["total"]))
        for label, cells in sorted(zip(labels, self.usage), key=lambda row: -sum(row[1])):
            print(line(label, cells))
        print(line("all", [sum(col) for col in zip(*self.usage)]))


def build_tool_paths():
    """(cwd|file, command, path) for what build tools hold: their working
    directory, and open files under a .build. A Gradle daemon's cwd is
    ~/.gradle/daemon, so only its open files tell."""
    out = run("lsof", "-w", "-n", "-P", "-c", "java", "-c", "swift", "-c", "skip", "-c", "clang",
              "-c", "xcodebuild", "-Fcfn").stdout
    found, cmd, fd = [], "", ""
    for line in out.splitlines():
        kind, value = line[:1], line[1:]
        if kind == "c":
            cmd = value
        elif kind == "f":
            fd = value
        elif kind == "n":
            if fd == "cwd":
                found.append(("cwd", cmd, value))
            elif "/.build/" in value:
                found.append(("file", cmd, value))
    return found


def building_in(tools, wt, entries):
    """The build tool working in worktree wt or holding a file under one of entries."""
    for kind, cmd, path in tools:
        if kind == "cwd" and under(path, wt):
            return cmd
        if kind == "file" and any(under(path, e) for e in entries):
            return cmd
    return None


# --- run --------------------------------------------------------------------

def target_path(arg):
    """Absolute path for a worktree argument: a bare name lives in WORKTREES."""
    arg = arg.rstrip("/") or "/"
    if "/" not in arg and arg not in (".", ".."):
        return f"{WORKTREES}/{arg}"
    p = Path(CALLER_DIR, arg)
    if p.is_dir():
        return str(p.resolve())
    if p.parent.is_dir():
        # git records worktrees by physical path.
        return f"{p.parent.resolve()}/{p.name}"
    return str(p)


def main():
    global args, PAINT, RESET, MAIN, WORKTREES, CALLER_DIR, lock_script, signing_helper
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-h", "--help", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--orphans", action="store_true")
    parser.add_argument("--reclaim", action="store_true")
    parser.add_argument("--base", action="append", default=[])
    parser.add_argument("targets", nargs="*")
    args = parser.parse_args()
    # In step with the refusals on stderr.
    sys.stdout.reconfigure(line_buffering=True)
    if args.help:
        print(__doc__.strip())
        return 0
    args.base = args.base or list(PROTECTED)
    if args.orphans:
        if args.targets:
            die("--orphans takes no worktree")
    else:
        if not args.targets:
            die("no worktree given (see --help)")
        if args.reclaim:
            die("--reclaim goes with --orphans")

    if sys.stdout.isatty() and not os.environ.get("NO_COLOR"):
        PAINT, RESET = ("\033[33m" if args.dry_run else "\033[32m"), "\033[0m"

    common = git(ROOT, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common.returncode:
        die(f"{ROOT} is not in a git repository")
    MAIN = str(Path(common.stdout.strip()).parent.resolve())
    WORKTREES = f"{os.path.dirname(MAIN)}/FurAffinity-worktrees"
    try:
        CALLER_DIR = os.getcwd()
    except FileNotFoundError:
        CALLER_DIR = MAIN

    lock_script = str(LOCK_SCRIPT) if os.access(LOCK_SCRIPT, os.X_OK) else ""
    targets = [target_path(t) for t in args.targets]
    # Running from inside a worktree being removed: the lock script goes with it,
    # so run a copy. Python has already read this file and its imports.
    if lock_script and any(under(str(ROOT), t) for t in targets):
        tmp = tempfile.mkdtemp(prefix="fa-cleanup.")
        atexit.register(shutil.rmtree, tmp, True)
        lock_script = shutil.copy2(lock_script, tmp)
        signing_helper = shutil.copy2(signing_helper, tmp)
    os.chdir(MAIN)

    status = 0
    if args.orphans:
        Orphans().run()
    else:
        for t in targets:
            if not clean_worktree(t):
                status = 1

    print(painted(f"{'would reclaim' if args.dry_run else 'reclaimed'} {human(total_kb)}"))
    if caller_removed:
        print(f"note: your shell is in a deleted directory — cd {MAIN}")
    return 1 if failed or status else 0


if __name__ == "__main__":
    sys.exit(main())
