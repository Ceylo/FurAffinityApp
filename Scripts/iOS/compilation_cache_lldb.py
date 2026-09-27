"""Debugs a build of the FA Compilation Cache toolchain.

Its compiles record /^src, /^derived, /^sdk, /^toolchain and /^xcode instead of
real paths, and a cache hit replays them unchanged, so the debugger maps them
back to this worktree: source-map for files and breakpoints, a Clang VFS overlay
for the modules `po` imports. A build without the toolchain records real paths,
which none of this touches. See COMPILATION_CACHE.md.
"""

import hashlib
import os
import plistlib
import subprocess

import lldb

WORKTREE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOLCHAIN = os.path.expanduser("~/Library/Developer/Toolchains/FACompilationCache.xctoolchain")
DERIVED_DATA = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
SCRATCH = os.path.expanduser("~/Library/Caches/FACompilationCache/lldb")


def _derived_data_dir():
    """This worktree's most recently used DerivedData directory, if any."""
    found = []
    for name in os.listdir(DERIVED_DATA) if os.path.isdir(DERIVED_DATA) else []:
        info = os.path.join(DERIVED_DATA, name, "info.plist")
        try:
            with open(info, "rb") as f:
                workspace = plistlib.load(f).get("WorkspacePath", "")
        except (OSError, plistlib.InvalidFileException):
            continue
        if os.path.dirname(workspace) == WORKTREE:
            found.append((os.path.getmtime(info), os.path.dirname(info)))
    return max(found)[1] if found else None


def _run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()


def _mappings(sdk_name):
    developer = _run("xcode-select", "-p")
    pairs = [("/^src", WORKTREE), ("/^toolchain", TOOLCHAIN), ("/^xcode", developer)]
    derived = _derived_data_dir()
    if derived:
        pairs.append(("/^derived", derived))
    sdk = _run("xcrun", "--sdk", sdk_name, "--show-sdk-path")
    if sdk:
        pairs.append(("/^sdk", sdk))
    return pairs


def _overlay(pairs):
    roots = ",\n".join(
        f"    {{ 'type': 'directory-remap', 'name': '{ph}', 'external-contents': '{real}' }}"
        for ph, real in pairs
    )
    text = ("{ 'version': 0, 'case-sensitive': 'false', 'fallthrough': true,\n"
            f"  'roots': [\n{roots}\n  ] }}\n")
    os.makedirs(SCRATCH, exist_ok=True)
    path = os.path.join(SCRATCH, hashlib.md5(text.encode()).hexdigest() + ".yaml")
    if not os.path.exists(path):
        with open(path + ".tmp", "w") as f:
            f.write(text)
        os.replace(path + ".tmp", path)
    return path


def _apply(debugger, sdk_name):
    pairs = _mappings(sdk_name)
    source_map = " ".join(f'"{ph}" "{real}"' for ph, real in pairs)
    debugger.HandleCommand(f"settings set target.source-map {source_map}")
    debugger.HandleCommand(
        f'settings set -- target.swift-extra-clang-flags "-ivfsoverlay {_overlay(pairs)}"')


class PerTarget:
    """Redoes the mapping for the stopped target's SDK — simulator or device —
    before the IDE evaluates anything. The init-time default assumes the simulator."""

    def __init__(self, target, extra_args, internal_dict):
        self.done = False

    def handle_stop(self, exe_ctx, stream):
        if not self.done:
            self.done = True
            triple = exe_ctx.target.GetTriple() or ""
            if "simulator" not in triple:
                _apply(exe_ctx.target.GetDebugger(), "iphoneos")
        return True


def __lldb_init_module(debugger, internal_dict):
    # Every debug/test session of this shared scheme loads this file, whether or
    # not this machine ever opted into the toolchain; skip the mapping (and the
    # xcode-select/xcrun subprocess calls) rather than pay for or risk breaking
    # unrelated debugging when it wasn't.
    if not os.path.isdir(TOOLCHAIN):
        return
    # Set before any target exists, so a breakpoint by full path binds when its
    # module loads.
    _apply(debugger, "iphonesimulator")
    debugger.HandleCommand(f"target stop-hook add -P {__name__}.PerTarget")
