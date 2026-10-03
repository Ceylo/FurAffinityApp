# Compilation cache (iOS)

Debug builds turn on Xcode's compilation cache (`COMPILATION_CACHE_ENABLE_CACHING`,
project-level, Debug only; Xcode extends it to the package targets itself). The cache
lives in the machine-wide `~/Library/Developer/Xcode/DerivedData/CompilationCache.noindex`
and outlives Clean Build Folder: a clean rebuild of a worktree went from 43.7 s to
23.7 s. On its own it helps that one worktree only, because every cache key holds the
checkout's path and its DerivedData directory's path (which also holds the package
checkouts).

## Sharing it across worktrees

```
Scripts/iOS/compilation-cache-toolchain.sh
```

installs the **FA Compilation Cache** toolchain. Select it in Xcode ▸ Toolchains, or
for the command line:

```
TOOLCHAINS=dev.fa.compilation-cache xcodebuild build -scheme FurAffinity -destination "id=$(Scripts/iOS/simulator.sh --udid)"
```

A fresh worktree then replays every Swift compile another worktree already did: all
322 of them, 53.4 s of build down to 27.9 s. Without the toolchain everything still
builds, with a per-worktree cache.

What it does, and why each part is needed on Xcode 26.6:

- **Prefix maps.** The toolchain's `OverrideBuildSettings` map the workspace's parent
  directory to `/^src` and the DerivedData directory to `/^derived`. Only toolchain
  overrides reach package targets; the project's own settings do not, and `TOOLCHAINS`
  in `project.pbxproj` swaps the binaries without applying the overrides.
- **A `swift-frontend` shim** (`Scripts/iOS/compilation-cache-swift-frontend`). The
  driver leaves `-debug-module-path`, `-module-cache-path`,
  `-const-gather-protocols-file` and the paths inside the explicit module map
  unmapped, and each of them is part of the key. The shim maps them before the
  frontend computes it. Xcode's own remarks keep saying "Replay cache miss": Xcode
  queries the cache with the unshimmed arguments first; the hit is the frontend's.
- **A clone of Xcode's toolchain** rather than a wrapper around it: the driver takes
  the toolchain's location from the frontend's, so the shim must live inside one. It
  is an APFS clone and costs no disk. The scheme's build pre-action re-clones it after
  an Xcode update.

## Opting in

The toolchain is per machine: nothing installs it but the script above, and the
scheme's pre-action only refreshes one that is already installed. Without it, a clone
still gets the per-worktree cache, and the LLDB init file only chains to
`~/.lldbinit`.

Xcode ▸ Toolchains is one preference for all of Xcode, not per project, so every
worktree opened in Xcode uses it (`xcodebuild` ignores that preference and needs
`TOOLCHAINS`). Other projects build as with Xcode's default toolchain unless they turn
on `COMPILATION_CACHE_ENABLE_CACHING`. If they do, their objects get `/^src` paths that
nothing maps back, so their breakpoints don't bind: select the default toolchain for
them.

After an Xcode update, build FurAffinity first, or run the script. Until then the
toolchain is the old Xcode's, for every project. The shim is written against Xcode
26.6's driver. A newer driver may leave a different path unmapped, which only turns
cross-worktree hits into misses: check a new worktree's first build with
`-Rcache-compile-job` (`replay` is a hit, `cache miss` is not). Building with two
Xcodes in turn re-clones the toolchain at every switch.

## Debugging

Objects built this way name `/^src/…` files, and a cache hit replays another
worktree's objects byte for byte. The scheme's LLDB init file
(`Scripts/iOS/compilation-cache.lldbinit`) maps the placeholders back to this worktree:
`target.source-map`, so a breakpoint set by path binds and opens this worktree's file,
and a Clang VFS overlay, without which `po` cannot import the SDK. It sources
`~/.lldbinit-Xcode` or `~/.lldbinit` first, since Xcode reads it in their place. For a
bare `lldb`, run `command source Scripts/iOS/compilation-cache.lldbinit`.

It maps only when the app's newest object file records `/^src`, that is, when the
last build used the toolchain. LLDB also rewrites a breakpoint's path through
`target.source-map`, so mapping a build with real paths would leave every breakpoint
Xcode sets unresolved.

## Previews

A SwiftUI preview's thunk compile reuses the cached Debug job's command line but
appends `-no-cache-compile-job`, so the frontend opens its inputs from disk, where
`/^src` does not exist. The shim sees that flag and maps every placeholder back to
its real path (from the job's own `-cache-replay-prefix-map` pairs) instead of
mapping the job further. The preview build is therefore uncached, and the shared
cache is untouched. Three other inputs carry placeholders as well: the `-filelist`
file, which the shim rewrites into a copy; and the cached `.pcm`s' header paths,
which it serves through a `directory-remap` `-vfsoverlay`. The canvas also runs this
compile with `HOME` unset, so the shim derives the home directory from its own path.

That overlay must come **before** Xcode's own, which swaps the source for the
thunk. A later overlay shadows Xcode's, so the plain source compiles instead. Its
`#Preview` registry symbols are then identical to the app object's (they are named
by line, and the thunk's lines are offset by its header). The canvas looks for the
thunk's registry, misses it, and reports the preview as *excluded from the build*.
To diagnose, compare the `line` of `performUpdate` with `Found preview registry:` in
the preview simulator's log
(`xcrun simctl --set ~/Library/Developer/Xcode/UserData/Previews/Simulator\ Devices
spawn <udid> log stream …`). `RenderPreview` from the Xcode MCP is no proxy: it
rendered while the canvas failed.

Reinstalling the toolchain makes Xcode fall back to the default one: re-select it
in Xcode ▸ Toolchains.

## Size

`COMPILATION_CACHE_LIMIT_SIZE = 2500M` makes Xcode start a new CAS generation once the
current one outgrows it, copying forward whatever it reads from the previous one.
`xcodebuild` never deletes the generation before last, so the scheme's build pre-action
(`Scripts/iOS/compilation-cache-prune.sh`) does, with `llvm-cas --prune`. That keeps the
cache under 2 × (limit + one clean build's writes, about 690 MB) ≈ 6.4 GB, inside the
6.5 GB cap: 1.5 × a fresh worktree's DerivedData (4,346,572 KB, 2026-09-26).

## Removing it

Delete `~/Library/Developer/Toolchains/FACompilationCache.xctoolchain` and
`~/Library/Caches/FACompilationCache`, and select Xcode's default toolchain again.
