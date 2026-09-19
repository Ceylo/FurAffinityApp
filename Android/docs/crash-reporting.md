# Crash reporting

Sentry, one project for both platforms (`ceylo-furaffinity-app`, EU region), told
apart by `os.name`. A crash arrives as a **symbolicated call stack with
`File.swift:line`** — including the Swift frames inside the Android `.so` files,
which is the reason for the service choice: Sentry symbolicates server-side from
DWARF, and demangles Swift.

## Shape

One shared configuration, two SDKs:

- `FurAffinity/Helpers/CrashReporting.swift` builds `CrashReportingConfiguration` —
  DSN, `release` (`<app id>@<version>`), `environment` (`debug`/`release`), and
  `reportsSince` — then calls `startPlatformCrashReporter(_:)`.
- `Helpers/iOS/CrashReporting+iOS.swift` starts **sentry-cocoa**;
  `Helpers/Android/CrashReporting+Android.swift` drives the Kotlin
  `FACrashReportingBridge`, which starts **sentry-android**. Manifest auto-init is
  off (`io.sentry.auto-init=false`): Swift decides whether reporting runs at all.
- Nothing starts on the placeholder DSN, so a development build reports nothing.
  The real DSN is never committed; see § Three channels for where each build gets
  one. It is not much of a secret — it can only *send* events to this project,
  while `SENTRY_AUTH_TOKEN` reads and administers it.
- `CrashReporting.start` is the first thing both entry points do — on Android right
  after `installDefaultsSuite()`, since it reads a `Defaults` key.

Collected: stack trace, device model, OS and app version, and the SDK's random
per-install id. Not collected: `sendDefaultPii` is off, no screenshots, no view
hierarchy, no tracing, no network breadcrumbs, and no application log (see
§ No breadcrumbs). Approximate location is the one thing neither SDK controls —
see § Two required project settings.

## Three channels

The app ships three ways, and each has to arrive at the same two things: a real
DSN compiled in, and its symbols on the server.

| Channel | Built | DSN from | Symbols uploaded by |
|---|---|---|---|
| IPA for AltStore Classic | `.github/workflows/release.yml`, on a tag | `${{ secrets.SENTRY_DSN }}`, `sed` into `CrashReportingSecrets.swift` | the archive's build phase, below |
| App Store Connect → AltStore PAL | locally, Xcode archive (or `xcodebuild archive`) | the distribution stash | the same build phase |
| Android APK | locally, `Scripts/Android/build-release-apk.sh` | the distribution stash (`$SENTRY_DSN` overrides) | the Sentry Gradle plugin, during `skip export` |

Both local channels apply `📱For App Store distribution`, so the DSN lives there
with the app id and the Amplitude key. CI has no stash, which is why the workflow
still seds its own in. Either way `CrashReportingSecrets.swift` keeps the
placeholder in git, and both local paths revert the working tree afterwards.

### The archive-only build phase

The `FurAffinity` target's **Upload dSYMs to Sentry** run script phase is the
whole iOS upload, for both iOS channels. Its first line is

```sh
[ "$ACTION" = install ] || exit 0
```

— Xcode sets `ACTION=install` when archiving and at no other time, so Debug and
ordinary Release builds stop there. The phase then fails the archive, loudly,
if `sentry-cli` is missing or no token is available; a release that silently
skips its upload is the failure mode worth paying for.

The phase declares `$DWARF_DSYM_FOLDER_PATH/$DWARF_DSYM_FILE_NAME` as an input,
which is what orders it after `dsymutil`: delete `Fur Affinity.app.dSYM` and
re-archive, and the phase sees the freshly regenerated one rather than nothing.

Authentication is `SENTRY_AUTH_TOKEN` on CI, and a git-ignored `.sentryclirc` in
the project root for a **GUI archive**, which inherits no environment:

```
printf '[auth]\ntoken=<org auth token>\n' > .sentryclirc
```

`${CI:+--wait}` makes only CI wait for server-side processing.

#### Why the script sandbox is off for Release

`ENABLE_USER_SCRIPT_SANDBOXING = NO`, on the **app target's Release configuration
only** — Debug keeps it, and so does `NotificationContent` in both configurations
(`xcodebuild -showBuildSettings` confirms all three). The app target has exactly
one run script phase, this one, so nothing else gives up the protection.

It is off because no declaration can make it work. Xcode's generated profile is
`(allow default)` with *subpath* denies on the build directories, including the
one the dSYMs are in:

```
(deny file-read* file-write* (subpath (param "CONFIGURATION_BUILD_DIR")) …)
…
(allow file-read* (literal (param "SCRIPT_INPUT_FILE_0")))
```

Declared inputs come back as `literal` — the node itself, not what is under it.
A dSYM is a *bundle*, so `Contents/Resources/DWARF/Fur Affinity` stays denied
however it is declared; declaring the whole folder instead changes nothing, for
the same reason. Sandboxed, `sentry-cli` authenticates, reaches
`chunk-upload/` over the network and then dies on `error: Operation not permitted
(os error 1)` — with no kernel log entry, since the profile does not report. With
the setting off the same archive prints `Found 76 debug information files` and
uploads them.

`$DWARF_DSYM_FOLDER_PATH` holds exactly what the archive's `dSYMs` folder does —
the app, the extension and the 11 embedded frameworks. FAKit, FAPages and
FALogging link statically into the app, so their debug info is in
`Fur Affinity.app.dSYM`.

## Consent

On by default, with a "Send crash reports" toggle in Settings → Privacy, backed by
`Defaults[.crashReportingEnabled]`. Turning it off calls `SentrySDK.close()` /
`Sentry.close()` at once; turning it on applies at the next launch.

`Defaults[.crashReportingEnabledSince]` is the second half of that promise. Android
reads the OS's record of the **last native crash (its tombstone) and the last ANR**
at startup, whether or not reporting was on when they happened — so switching the
toggle back on would otherwise send the crash captured while the user had opted
out. Both SDKs get a `beforeSend` that drops any event older than that timestamp.

The legal basis is legitimate interest (GDPR Art. 6(1)(f)), which is why the
collection is this small; the project also has *Prevent Storing of IP Addresses*
on. `Privacy Policy.md` names Sentry.

### Two required project settings, not one

*Prevent Storing of IP Addresses* does less than its name suggests. Sentry
geocodes the address **before** scrubbing it and keeps the result, so an event
arrives with `user.ip_address: null` and a populated
`user.geo` — country, region and **city**. Neither SDK sends any of this
(`sendDefaultPii` is off on both and neither sets a user), so nothing in this
repo can prevent it: it is added server-side and only a server-side rule removes
it. That rule is, in Project Settings → Security & Privacy → Advanced Data
Scrubbing:

```
[Remove] [Anything] from [$user.geo.**]
```

Upstream tracks this as getsentry/sentry#92201. Scrubbing applies at ingest, so
the rule only affects events received after it, and events that already carry a
location keep it until they are deleted or age out.

`Scripts/check-crash-reporting.sh` asserts both halves on every case — no
`user.geo` and a null `user.ip_address` — because a project setting is exactly
the kind of thing that is silently true until someone changes it, and only a
fresh event can show it is still in force.

## Android: tombstones, not the NDK signal handler

A Swift crash on Android is a native signal (`fatalError` traps with `SIGTRAP`).
Two integrations can catch it, and **only one may be on**:

- **Tombstones** (`isTombstoneEnabled`), Android 12+: the OS collects the crash out
  of process and the SDK reads it at the next start. Richer — every thread's stack,
  client-side symbolication of system libraries — and safer.
- **The NDK signal handler** (`isEnableNdk`), below Android 12 (minSdk is 28).

With both on, each sends its own report of the same crash and the SDK's merge step
fails (`No matching native event found for tombstone`), so one crash becomes two
issues. `FACrashReportingBridge` picks by API level.

`dist` is set explicitly to the version code: the tombstone path otherwise derives
an invalid one from `release` and the event arrives with an `invalid_data` error.

## Symbols

| What | Uploaded by | When |
|---|---|---|
| The DSN | the distribution stash, or `sed` from `$SENTRY_DSN` — see § Three channels | every distributed build |
| iOS dSYMs (+ sources) | the `FurAffinity` target's "Upload dSYMs to Sentry" build phase | every archive, CI or local |
| Android `.so` (+ sources) and the R8 mapping | the Sentry Gradle plugin, during `skip export` | release and `profile` builds, when `SENTRY_AUTH_TOKEN` is set |

The Android upload takes the **unstripped** libraries from
`merged_native_libs/…`, while the APK ships stripped ones. That works because
stripping preserves the GNU BuildID, which is what Sentry matches on.
`Scripts/Android/build-release-apk.sh` refuses to build without
`SENTRY_AUTH_TOKEN` or without a DSN in the distribution stash: a release that
cannot be symbolicated is worse than no release.

The plugin uploads every ABI's libraries, not just `arm64-v8a`, because the merge
step runs before the ABI filter.

### Line numbers, and why `-disable-cmo`

Swift's **cross-module optimization** is on by default for `-O` whole-module
builds. It copies small public functions into the module that calls them — and the
copies carry **no line table at all**. A crash inside one symbolicates to the right
function and `<compiler-generated>:0`, with no file and no line, on both platforms.
`llvm-symbolizer` reads the shipped library the same way, so no upload can fix it.

`FAKit`, `FAPages`, `FALogging` and `OSCompat` therefore build release with
`-disable-cmo` (their `Package.swift`). Cost: +21 KB on `libFurAffinityUI.so`
(+1.0 %), ~32 KB over all our libraries, and **no measurable parse time** —
alternating the two APKs on one emulator session, the median
`FAPages: Submission Preview Parsing` (72+ per feed load) was 0.11/0.11 ms with
CMO on and 0.16/0.09 ms with it off, i.e. inside the run-to-run spread. `swiftForceUnwrapFAKit` in the checker is
the regression test — it asserts `CrashTestSite.swift:13`, which only FAKit's own
copy of that function can produce.

`unsafeFlags` is allowed here because all three are local packages; a remote
dependency on them would refuse to resolve.

### In-app frames

On Android every library is loaded out of `base.apk`, so Sentry cannot tell app
code from library code by path. The project's **Stack Trace Rules** (Project
Settings → Issue Grouping) do it:

```
stack.abs_path:**/FurAffinity/** +app
stack.abs_path:**/FAKit/Sources/** +app
stack.abs_path:**/FALogging/Sources/** +app
```

Kotlin frames come from `options.addInAppInclude("fur.affinity.ui")`. iOS needs
none of this: sentry-cocoa marks the app's own images, plus the FAKit / FAPages /
FALogging frameworks named in `inAppIncludes`.

## No breadcrumbs

Neither SDK receives the application log. `FALogging` renders every interpolation
eagerly (`FALogMessage`) and has no privacy annotations, so forwarding log lines
would send usernames, submission ids and full URLs along with each crash. The log
stays where it was: Settings → Export Application Logs, on request.

Kotlin frames have line numbers but **no source text**, by choice. Swift frames do
carry source text, from `--include-sources`; see § Kotlin source context for why
Kotlin's is left off.

### Kotlin source context

`includeSourceContext = sentryUploads` is set and the tasks really do register —
`sentryCollectSources*`, `sentryBundleSources*`, `sentryUploadSourceBundle*`, all
present in `:app:tasks --all` once `SENTRY_AUTH_TOKEN` is set, which is what gates
them. What the bundle does not do is *resolve*. Sentry's layout rule is that the
package declaration and the file tree must match, and the nine bridges declare
`package fur.affinity.ui` while sitting flat in `Android/app/src/main/kotlin/`, so
the bundle comes out keyed on bare filenames:

```
files/_/_/FACrashReportingBridge.jvm   →  url "~/FACrashReportingBridge.jvm"
```

A JVM frame is looked up under its package path, so nothing matches and the upload
is dead weight. Moving the files to `src/main/kotlin/fur/affinity/ui/` fixes the
keys — measured, the same nine files come out as
`~/fur/affinity/ui/FACrashReportingBridge.jvm` — and costs almost nothing: **27 ms**
of build time for the three tasks together (21 ms bundle, 5 ms collect, 1 ms id),
a **21 KB** upload, and **58 bytes** of APK, one `io.sentry.bundle-ids` line in
`assets/sentry-debug-meta.properties`.

It is not done, because the price is not the build time: it is nine files leaving
the one flat directory that `Scripts/Android/logs.sh` globs for bridge `TAG`s and
that `Scripts/check-crash-reporting.sh` and the docs name by path, in exchange for
source text on Kotlin frames that already carry file and line — and there are nine
Kotlin files against a whole app of Swift. Revisit if the Kotlin layer grows.

## Verifying it

`Scripts/check-crash-reporting.sh ios|android [--no-build] [case…]` is the proof,
not a claim in a commit message. Per case it builds the way shipping does (symbols
uploaded), crashes the app, relaunches so the SDK sends the stored report, fetches
that exact event from the Sentry API and asserts on it:

- no `native_missing_dsym` / `native_bad_dsym` / `proguard_missing_mapping` / … ;
- a frame whose function, file and **line** match the `// CRASH-TEST-SITE <case>`
  marker in the source — grepped, so it cannot drift — plus `in_app` and, for
  Swift, the source line itself;
- exactly one event per crash (this is what caught the tombstone/NDK duplicate);
- `optOut`: crash with the setting off, then turn it back on, and require that
  **nothing** is reported.

Each event's JSON lands in `.build/crash-reporting/` as the evidence.

```
export SENTRY_DSN=… SENTRY_AUTH_TOKEN=… SENTRY_READ_TOKEN=…   # read needs event:read, org:read
Scripts/check-crash-reporting.sh android
Scripts/check-crash-reporting.sh ios
```

Android runs the **`profile`** variant: release code, R8'd and stripped, but signed
with the debug key and — unlike a release build — it honours the crash-test intent
extras. `MainActivity` is exported, so any app could send them; a release build
ignores them (`BuildConfig.BUILD_TYPE == "release"`). iOS uses launch arguments,
which only `simctl`/`devicectl`/Xcode can pass, so they stay live in Release.

The crash cases live in `FurAffinity/Helpers/CrashTest.swift` (and
`FAKit/Sources/FAKit/CrashTestSite.swift`): `fatalError` on the main thread, a
force unwrap inside FAKit, an out-of-range index on a detached thread, and, on
Android, a Kotlin exception.

Last full run (2026-09-17, one event per crash, no symbolication errors). The
lines are each run's markers, which move as the files change:

| Case | Android | iOS |
|---|---|---|
| `swiftFatalError` | `CrashTest.swift:50` | `CrashTest.swift:62` |
| `swiftForceUnwrapFAKit` | `CrashTestSite.swift:13` | `CrashTestSite.swift:13` |
| `swiftBackgroundThread` | `CrashTest.swift:56`, non-main | `CrashTest.swift:56`, non-main |
| `kotlinException` | `FACrashReportingBridge.kt:75` | — |
| `optOut` | nothing reported | nothing reported |
