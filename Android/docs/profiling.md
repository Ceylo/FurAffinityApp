# Profiling

The Instruments workflow, on the emulator: a CPU sampler, a system trace with our
signposts and memory counters, and a quick memory log.

| Instruments | Here | Viewer |
|---|---|---|
| Time Profiler | `profile.sh cpu` (simpleperf) | https://profiler.firefox.com |
| Points of Interest, Allocations over time | `profile.sh trace` (Perfetto) | https://ui.perfetto.dev |
| Memory gauge | `profile.sh mem` (`dumpsys meminfo`) | `meminfo.csv` |

## Why a `profile` build

A debug build puts the time in the wrong places: Swift is `-Onone` and ART runs
debuggable, which disables most of its compiler. A release build cannot be profiled
at all, and strips Swift symbols and obfuscates Kotlin. The `profile` build type in
`Android/app/build.gradle.kts` is release with three changes:

- **Profileable, not debuggable**, so simpleperf and heapprofd may attach.
- **Installed under the debug app's id and signed with the debug key**, so it
  replaces this worktree's debug app *as an update*: the container, its FA login
  and Cloudflare clearance survive both ways. A worktree whose app was never logged
  in still needs a login first — autologin parses nothing without one.
- **`-dontobfuscate`** (`proguard-rules-profile.pro`), so Kotlin frames keep their
  class names.

The APK's native libraries stay stripped, so memory numbers are realistic; the
scripts symbolize from the unstripped copies under
`.build/Android/app/intermediates/merged_native_libs/profile/`.

## Workflow

```
Scripts/Android/run.sh --profile          # build, install, AOT-compile, start
Scripts/Android/profile.sh cpu            # 20 s of CPU samples while you use the app
Scripts/Android/profile.sh cpu --launch   # restart the app under the profiler
Scripts/Android/profile.sh trace          # 20 s Perfetto trace + signpost summary
Scripts/Android/profile.sh trace --native-heap --compose
Scripts/Android/profile.sh mem            # type a label + Enter to tag a sample
Scripts/Android/run.sh                    # back to the debug build, same container
```

Every recording goes to `.build/profiles/<timestamp>-<command>/`. `profile.sh` refuses
a debuggable install, and holds the emulator lock so another worktree's build cannot
steal the CPU mid-recording.

`run.sh --profile` ends with `cmd package compile -m speed -f`, so a recording
measures compiled Kotlin rather than ART's JIT warming up. On the emulator that
takes about 8 minutes and can overrun dex2oat's 570 s limit; the script then warns
and the app stays on the install-time baseline-profile compile.

## `cpu`

simpleperf samples `cpu-clock` at 4 kHz — the emulator exposes no hardware counters —
with DWARF call graphs (`--fp` for frame pointers: cheaper, shallower). The script
converts `perf.data` to the Firefox Profiler format, applies R8's `mapping.txt`, and
pipes it through `swift-demangle --simplified`.

- **simpleperf follows the process that exists when recording starts.** Restart the
  app mid-recording and the new process is not sampled; use `--launch` to profile
  startup.
- **The mapping still matters with `-dontobfuscate`.** R8 keeps class names but merges
  classes and moves static methods between them, so without it a Compose frame can
  read `kotlin.ResultKt.moveGroup`. On a launch profile it corrected 219 frames.
- The first recording pulls system libraries into `binary_cache/` (the WebView APK
  alone takes a minute); later ones reuse what they can.

## `trace`

Writes two traces, both for https://ui.perfetto.dev, and prints a summary:

- **`signposts.pftrace` — start here.** `focus-trace.py` cuts the recording down to
  the app's process: its threads (named), its FAKit/FAPages signposts, its memory
  counters, and two CPU counters — **CPU: app** and **CPU: main thread**, the share
  of one core each used per 100 ms (up to 400% on the 4-core emulator), computed
  from the scheduler data. Scheduling itself, other processes, framework and Compose
  sections, and the frame timeline are gone, so a 17 MB trace becomes a few tracks.
- **`signposts.txt`**, the summary also printed at the end: per signpost, count,
  total, median, max and the threads it ran on (wall time, begin to end), then the
  app's and main thread's average and peak CPU, and the app's RSS at start, peak and
  end.
- **`fa.pftrace`**, the whole device, for when the context matters.

`focus-trace.py` also runs on its own, e.g. to keep Compose's sections:
`Scripts/Android/focus-trace.py fa.pftrace <app id> --prefix "Compose:" -o compose.pftrace`
(`--all-sections` keeps every section of the app).

The recording (`config.pbtxt` next to the trace) has:

- **ftrace** scheduling, plus atrace `view gfx am dalvik` and this app's own sections;
- **`linux.process_stats`** every 250 ms: the `mem.rss.anon`/`file`/`swap` counter
  tracks under each process, and thread names;
- **SurfaceFlinger frame timeline**;
- with `--native-heap`, **heapprofd** allocation samples for the app.

The profile variant also depends on `androidx.compose.runtime:runtime-tracing`;
`--compose` enables it by broadcast before recording, so every composable becomes a
section — thousands a second, which is why it is opt-in. That switch is per process:
a restart during the trace turns it off.

Perfetto's "No PTY" warning is harmless: the trace stops on its duration, not on
Ctrl-C.

### Signposts

`OSSignposter` on Android is `FALogging/Sources/OSCompat`'s, backed by
`ATrace_beginSection`/`ATrace_endSection`. Every FAPages parsing interval therefore
shows up as a slice on the thread that parsed, named `<category>: <name>`
(`FAPages: Submission Parsing`, `FAKit: AttributedString.init(FAHTML:)`, …). The
category prefix is what `focus-trace.py` filters on.

In `profile.sh cpu`, the parsers are not under `libFAPages.so`: in the release build
their code, and SwiftSoup's, lands in `libFAKit.so`. Search the call tree for
`Page.init` rather than by library.

**An interval must not span an `await`.** ATrace sections are a per-thread stack, and
the continuation after a suspension may run on another thread. An end on a different
thread than its begin is dropped, so the slice never closes rather than closing
someone else's. Every current call site begins and ends in one synchronous scope. When
no trace is recording, an interval costs one `ATrace_isEnabled()` call.

## `mem`

Samples `dumpsys meminfo <app>` every `--interval` seconds (default 2) and appends the
App Summary rows — Java Heap, Native Heap, Code, Stack, Graphics, Private Other,
System (PSS), TOTAL PSS, TOTAL RSS — to `meminfo.csv`, as raw KB (1024 bytes) with the
unit in each header. The terminal shows a subset, each column defined above the table,
sized in the largest unit that keeps the value at least 1 ("196.4 MB"). Text typed
while it runs, then Enter, lands in the next row's `label` column ("opened
submission"). Ctrl-C stops it.

For a live graph instead, Android Studio's Profiler → **View Live Telemetry** attaches
to the profileable app as well.

## What the emulator does and does not represent

- **CPU: relative cost, yes; absolute time, no.** The guest runs arm64 natively on
  Apple silicon, so which function dominates is trustworthy, but it shares the host's
  cores and gets slower whenever the host is busy — never compare durations across
  sessions.
- **GPU and frames: no.** Rendering goes through the host GPU's emulation layer;
  frame timelines show jank patterns, not a phone's frame budget.
- **Memory: relative growth, yes; absolute numbers, no.** The AVD image uses 16 KB
  pages where most phones use 4 KB, which rounds every mapping up, and graphics
  memory lives on the host.
