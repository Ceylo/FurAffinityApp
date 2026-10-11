#!/usr/bin/env python3
"""Seed a worktree's DerivedData/SourcePackages from a sibling worktree's, so a
fresh worktree skips SwiftPM's package resolution and checkout entirely.

Half of a fresh iOS build is package resolution: ~3.6 GB of unzipped binary
artifacts and ~29 git checkouts, none of which differ between worktrees pinned
to the same Package.resolved. So it is APFS-cloned (no disk cost), then the
sibling's DerivedData and worktree paths are rewritten to this one's.

Usage: Scripts/iOS/seed-source-packages.py [worktree]

  worktree   defaults to this script's own worktree

Idempotent and quiet on success. Exits 0 (and prints one line) if no sibling
qualifies, leaving normal package resolution to run. Never overwrites an
existing SourcePackages.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from fa_paths import DERIVED_DATA, derived_data_hash, workspace_path  # noqa: E402

RESOLVED = "FurAffinity.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"


def say(message):
    print(f"seed-source-packages: {message}")


def resolved_to_pins(workspace_state, package_resolved):
    """Whether workspace-state.json checked out every pin of Package.resolved.
    What the sibling resolved, not its Package.resolved: SwiftPM keeps a stale
    checkout's pins over a changed Package.resolved, and we'd copy them along."""
    deps = json.loads(workspace_state.read_text())["object"]["dependencies"]
    have = {d["packageRef"]["identity"]: d["state"].get("checkoutState", {}).get("revision")
            for d in deps}
    pins = json.loads(package_resolved.read_text())["pins"]
    return all(have.get(p["identity"]) == p["state"].get("revision") for p in pins)


def best_sibling(dst, resolved):
    """(DerivedData dir, worktree) of the most recently used sibling whose
    SourcePackages is resolved to exactly these pins, or None."""
    best, best_mtime = None, -1
    for info in DERIVED_DATA.glob("FurAffinity-*/info.plist"):
        dd_dir = info.parent
        if dd_dir == dst:
            continue
        workspace = workspace_path(dd_dir)
        if not workspace:
            continue
        worktree = Path(workspace).parent
        state = dd_dir / "SourcePackages/workspace-state.json"
        if not worktree.is_dir() or not state.is_file():
            continue
        mtime = info.stat().st_mtime
        if mtime <= best_mtime:
            continue
        try:
            if not resolved_to_pins(state, resolved):
                continue
        except (OSError, ValueError, KeyError):
            continue
        best, best_mtime = (dd_dir, worktree), mtime
    return best


def main(args):
    if args and args[0] in ("-h", "--help"):
        print(__doc__.strip())
        return
    # Logical, not resolved: Xcode hashes the path it was opened through.
    worktree = Path(os.path.abspath(args[0] if args else Path(os.path.abspath(__file__)).parents[2]))
    resolved = worktree / RESOLVED
    if not resolved.is_file():
        sys.exit(f"error: {resolved} not found")

    dst = DERIVED_DATA / f"FurAffinity-{derived_data_hash(worktree / 'FurAffinity.xcodeproj')}"
    if (dst / "SourcePackages").is_dir():
        return

    sibling = best_sibling(dst, resolved)
    if not sibling:
        say("no sibling worktree has a matching, resolved SourcePackages; resolving normally")
        return
    src, src_worktree = sibling

    # Built aside and swapped in with one rename, so a Ctrl-C or a full disk during
    # the multi-GB copy leaves no half-seeded SourcePackages at the path the exit
    # check above trusts.
    staging = dst / f"SourcePackages.seeding.{os.getpid()}"
    dst.mkdir(parents=True, exist_ok=True)
    try:
        # -c: an APFS clone, which shutil can't make.
        subprocess.run(["cp", "-Rc", str(src / "SourcePackages"), str(staging)], check=True)

        # Both paths only ever occur as a directory prefix. Anchoring on the "/" keeps
        # a sibling named android from also matching android-x.
        rewrites = [(f"{src}/", f"{dst}/"), (f"{src_worktree}/", f"{worktree}/")]
        files = [staging / "workspace-state.json",
                 *staging.glob("checkouts/*/.git/config"),
                 *staging.glob("checkouts/*/.git/objects/info/alternates")]
        for f in files:
            if not f.is_file():
                continue
            text = f.read_text()
            for old, new in rewrites:
                text = text.replace(old, new)
            # Replaced, not written: git leaves some of these read-only.
            tmp = f.with_name(f.name + ".seeding")
            tmp.write_text(text)
            shutil.copymode(f, tmp)
            os.replace(tmp, f)

        # rename(2), not a move: that would nest it inside a SourcePackages that Xcode
        # created meanwhile, and still succeed.
        try:
            os.rename(staging, dst / "SourcePackages")
        except OSError:
            say(f"Xcode created {dst}/SourcePackages meanwhile; leaving it")
            return
        say(f"seeded {dst}/SourcePackages from {src}")
    finally:
        shutil.rmtree(staging, ignore_errors=True)


if __name__ == "__main__":
    main(sys.argv[1:])
