# Crash reporting

Sentry, one project for both platforms (`ceylo-furaffinity-app`, EU region), told
apart by `os.name`. A crash arrives as a **symbolicated call stack with
`File.swift:line`** — including the Swift frames inside the Android `.so` files,
which is the reason for the service choice: Sentry symbolicates server-side from
DWARF, and demangles Swift.

## Shape

`FurAffinity/Helpers/CrashReporting.swift` builds the configuration and calls
`startPlatformCrashReporter(_:)`: sentry-cocoa in `Helpers/iOS/`, the Kotlin
`FACrashReportingBridge` in `Helpers/Android/`. Manifest auto-init is off
(`io.sentry.auto-init=false`), so Swift decides whether reporting runs at all; on
the placeholder DSN it does not, and a development build reports nothing. On
Android `CrashReporting.start` must follow `installDefaultsSuite()`, since it
reads a `Defaults` key.

Every event carries a **`commit` tag**, the short hash of the HEAD it was built
from, searchable as `commit:abc1234`. Many builds share one release, and
`release`/`dist` stay what the symbol and mapping uploads are matched against. iOS
stamps it through the `Commit Stamp` target, which writes a prefix header that the
app's preprocessed `Info.plist` expands into `FACommit`; Android through
`BuildConfig.GIT_COMMIT`. Both reach `FAAppVersion.commit`. There is no `-dirty`
suffix, since every shipped build is dirty on purpose (the stash, CI's DSN `sed`).
iOS sets it on the initial scope, so a crash report names the build that crashed;
an Android tombstone or ANR read back after an update gets the new build's tag, as
it gets its release.

What leaves the device is a stack trace, the device's fixed hardware, OS and app
version, the build's commit, and the SDK's random per-install id. `beforeSend` enforces that as an
**allowlist** of contexts rather than a list of things to strip, so whatever an
SDK starts collecting after an upgrade never leaves. That matters because the
defaults are wide — timezone, locale, connectivity, battery, free memory, granted
permissions, root/jailbreak status, on iOS a hash derived from
`identifierForVendor` — and because non-fatal events take a different path and
arrive with contexts crashes never carry (`culture`, holding timezone and locale,
is how that was found). Approximate location is the one thing neither SDK
controls; see § Project settings.

## Releasing

Three channels, each needing the same two things: a real DSN compiled in, and its
symbols on the server. Both local channels apply the `📱For App Store
distribution` stash, which is where the DSN lives beside the app id and the
Amplitude key; CI has no stash and seds its own in. `build.yml` gets no DSN —
nothing it builds is distributed, and one there would report CI's test runs to
production.

| Channel | What you do | Symbols |
|---|---|---|
| IPA for AltStore Classic | push a tag | the Upload dSYMs target, `secrets.SENTRY_AUTH_TOKEN` |
| App Store Connect → AltStore PAL | the procedure below | the same target |
| Android APK | `SENTRY_AUTH_TOKEN=… Scripts/Android/build-release-apk.sh` | the Sentry Gradle plugin, during `skip export` |

The Android script and the CI workflow need nothing remembered: each refuses to
produce an unreportable build, CI included, where a missing secret seds in an
empty DSN that the upload target rejects like the placeholder.

The **local iOS archive** is the one manual procedure. From a clean tree:

```
git stash apply <sha of the distribution stash>   # app id + Amplitude key + DSN
# Product > Archive, or `xcodebuild … archive`
git checkout -- .                                 # revert, always
```

You never run `sentry-cli` yourself; the upload is inside the archive. Two things
must hold **in the checkout you archive from**:

- the stash is applied, or the archive stops with `error:
  Secrets.swift holds no Sentry DSN`. Without that check the archive would
  upload its symbols, validate, ship, and report nothing;
- a `.sentryclirc` holds the org auth token, since a GUI archive inherits no
  environment and cannot see `$SENTRY_AUTH_TOKEN`. The project-root one is
  gitignored and so does not travel between worktrees or clones; `~/.sentryclirc`,
  what `sentry-cli login` writes, covers all of them. From a terminal, exporting
  the token works instead.

`release.yml` has not run since 1.18, so the first tagged release is also the
first exercise of the Upload dSYMs target. A failed upload fails the archive step,
and "Check the app's dSYM carries debug info" catches a dSYM that uploaded fine
with nothing in it.

### The archive-only target

The **Upload dSYMs** aggregate target is the whole iOS upload, for both iOS
channels. It depends on `FurAffinity`, and the scheme builds it for archiving only,
so Product > Archive and CI's `xcodebuild … archive` run it and nothing else does. It exits immediately unless `ACTION=install`, which
Xcode sets when archiving and at no other time, so Debug and ordinary Release
builds skip it. It then fails the archive loudly rather than skip an upload
silently. `${CI:+--wait}` makes only CI wait for server-side processing.

Its declared input `$(DWARF_DSYM_FOLDER_PATH)/Fur Affinity.app.dSYM` is what
orders it after `dsymutil`. That folder holds what the archive's `dSYMs` folder does —
the app, the extension and the embedded frameworks; FAKit, FAPages and FALogging
link statically, so their debug info is inside `Fur Affinity.app.dSYM`.

### Why two targets have the script sandbox off

`ENABLE_USER_SCRIPT_SANDBOXING` is a per-target setting; Xcode has no per-phase
switch. So the app target is sandboxed in both configurations, as is
`NotificationContent`, and the two steps that cannot run sandboxed each live in an
aggregate target of their own with it off: **Upload dSYMs** and **Commit Stamp**.
No declaration can make either work: Xcode's profile denies `SRCROOT` and the
build directories by *subpath* while granting declared inputs as `literal`, the
node itself and not what is under it —

```
(deny file-read* file-write* (subpath (param "CONFIGURATION_BUILD_DIR")) …)
(allow file-read* (literal (param "SCRIPT_INPUT_FILE_0")))
```

— and a dSYM is a bundle, so the DWARF file inside stays denied however it is
declared, the whole folder included; `--include-sources` reads every source file
under `SRCROOT` besides. Sandboxed, `sentry-cli` authenticates, reaches
`chunk-upload/` and dies on `error: Operation not permitted (os error 1)`, with no
kernel log entry because the profile denies without reporting. `git rev-parse`
reads many files under `.git`, which no list of literals names ahead of time.

The stamp rewrites its header only when the hash changes and is always out of
date, since HEAD moves without any declared input changing.

## Consent

On by default, with a "Send crash reports" toggle in Settings → Advanced. Turning
it off closes the SDK at once; turning it on applies at the next launch.

`Defaults[.crashReportingEnabledSince]` is the second half of that promise.
Android reads the OS's record of the **last tombstone and the last ANR** at
startup whether or not reporting was on when they happened, so switching the
toggle back on would otherwise send a crash captured while the user had opted out.
Both `beforeSend`s drop events older than that timestamp.

The legal basis is legitimate interest (GDPR Art. 6(1)(f)), which is why the
collection is this small. `Privacy Policy.md` names Sentry from 1.19.

### Project settings

Two of them, and the second is not optional.

*Prevent Storing of IP Addresses* does less than its name suggests: Sentry
geocodes the address **before** scrubbing it and keeps the result, so events
arrive with `user.ip_address: null` and a populated `user.geo` — country, region
and **city**. Neither SDK sends any of it, so nothing in this repo can prevent it.
Only a server-side rule can, in Project Settings → Security & Privacy → Advanced
Data Scrubbing:

```
[Remove] [Anything] from [$user.geo.**]
```

Upstream tracks this as getsentry/sentry#92201. It went on 2026-09-19; before it
every event carried `city=Angoulême`, after it `"geo": {}`. Scrubbing applies at
ingest, so it only affects events received after it.

The checker asserts both halves on every case, because a project setting is
silently true until someone changes it and only a fresh event shows otherwise.

## Android: tombstones, not the NDK signal handler

A Swift crash on Android is a native signal (`fatalError` traps with `SIGTRAP`).
Two integrations can catch it and **only one may be on**: tombstones
(`isTombstoneEnabled`, Android 12+), where the OS collects the crash out of
process and the SDK reads it at the next start — richer and safer — or the NDK
signal handler (`isEnableNdk`) below that. With both on, each sends its own report
and the merge fails (`No matching native event found for tombstone`), turning one
crash into two issues. `FACrashReportingBridge` picks by API level.

`dist` is set explicitly to the version code: the tombstone path otherwise derives
an invalid one from `release` and the event arrives with an `invalid_data` error.

## Symbols

The Android upload takes the **unstripped** libraries from `merged_native_libs/…`
while the APK ships stripped ones, which works because stripping preserves the GNU
BuildID that Sentry matches on. It covers every ABI, not just `arm64-v8a`, because
the merge step runs before the ABI filter.

### Line numbers, and why `-disable-cmo`

Swift's **cross-module optimization** is on by default for `-O` whole-module
builds. It copies small public functions into the module that calls them, and the
copies carry **no line table at all** — a crash inside one symbolicates to the
right function and `<compiler-generated>:0`, on both platforms. `llvm-symbolizer`
reads the shipped library the same way, so no upload can fix it.

`FAKit`, `FAPages`, `FALogging` and `OSCompat` therefore build release with
`-disable-cmo` (`unsafeFlags` is allowed only because they are local packages).
Cost: ~32 KB over all our libraries and **no measurable parse time** — alternating
the two APKs on one emulator session, the median `FAPages: Submission Preview
Parsing` was 0.11/0.11 ms with CMO on and 0.16/0.09 ms with it off, inside the
run-to-run spread. `swiftForceUnwrapFAKit` is the regression test: it asserts
`CrashTestSite.swift:13`, which only FAKit's own copy of that function produces.

### In-app frames

On Android every library loads out of `base.apk`, so Sentry cannot tell app code
from library code by path. The project's **Stack Trace Rules** (Project Settings →
Issue Grouping) do it:

```
stack.abs_path:**/FurAffinity/** +app
stack.abs_path:**/FAKit/Sources/** +app
stack.abs_path:**/FALogging/Sources/** +app
```

Kotlin frames come from `addInAppInclude`. iOS needs none of this: sentry-cocoa
marks the app's own images plus the frameworks in `inAppIncludes`.

## No breadcrumbs, no log

Both SDKs collect breadcrumbs by default — touches, screen and lifecycle changes,
battery and connectivity, network requests — and attach the last hundred to each
event. None of that is on the privacy policy's list, so automatic collection is
off with `maxBreadcrumbs = 0` as the backstop. Session tracking is off for the
same reason: it would send an envelope on every launch, so release-health numbers
stay empty.

Neither SDK receives the application log either. `FALogging` renders every
interpolation eagerly and has no privacy annotations, so forwarding lines would
send usernames, submission ids and full URLs with each crash. The log stays at
Settings → Export Application Logs, on request.

### Kotlin source context

Swift frames carry source text from `--include-sources`. Kotlin frames have line
numbers but no text, by choice.

The `sentryBundleSources*` tasks do register — they are gated on
`SENTRY_AUTH_TOKEN`, which is why they had never been seen. What the bundle does
not do is *resolve*: Sentry requires the package declaration and the file tree to
match, and the bridges declare `package fur.affinity.ui` while sitting flat in
`Android/app/src/main/kotlin/`, so the bundle is keyed on bare filenames —
`~/FACrashReportingBridge.jvm`, where a JVM frame is looked up under its package
path. Moving them to `src/main/kotlin/fur/affinity/ui/` fixes the keys (measured:
it does, for 27 ms of build time, a 21 KB upload and 58 bytes of APK).

It is not done because the cost is not the build time: it is nine files leaving
the flat directory that `Scripts/Android/logs.sh` globs for bridge `TAG`s and that
`check-crash-reporting.sh` names by path, bought for source text on frames that
already carry file and line. Revisit if the Kotlin layer grows.

## Verifying it

`Scripts/check-crash-reporting.sh ios|android [--no-build] [case…]` is the proof,
not a claim in a commit message. Per case it builds the way shipping does, crashes
the app, relaunches so the SDK sends the stored report, fetches that exact event
from the API and asserts on it:

- no `native_missing_dsym` / `proguard_missing_mapping` / … ;
- a frame whose function, file and **line** match the `// CRASH-TEST-SITE <case>`
  marker — grepped from the source, so it cannot drift — plus `in_app` and, for
  Swift, the source line itself;
- exactly one event per crash (this caught the tombstone/NDK duplicate);
- no location, no IP, no breadcrumbs, and no context outside the allowlist;
- `optOut`: crash with the setting off, turn it back on, require that **nothing**
  is reported.

Each event's JSON lands in `.build/crash-reporting/` as the evidence.

```
export SENTRY_DSN=… SENTRY_AUTH_TOKEN=… SENTRY_READ_TOKEN=…   # read needs event:read, org:read
Scripts/check-crash-reporting.sh android
Scripts/check-crash-reporting.sh ios
```

Android runs the **`profile`** variant: release code, R8'd and stripped, signed
with the debug key, and — unlike a release build — it honours the crash-test
intent extras. `MainActivity` is exported, so any app could send them; a release
build ignores them. iOS uses launch arguments, which only
`simctl`/`devicectl`/Xcode can pass, so they stay live in Release.

The cases live in `FurAffinity/Helpers/CrashTest.swift` and
`FAKit/Sources/FAKit/CrashTestSite.swift`. `appHang` is not a crash but a 5 s
main-thread hang, there because non-fatal events take a path crashes do not — it
is how the `culture` context was found.

Last full run (2026-09-19, one event per crash, no symbolication errors, no
location on any of them). The lines are each run's markers, which move as the
files change:

| Case | Android | iOS |
|---|---|---|
| `swiftFatalError` | `CrashTest.swift:62` | `CrashTest.swift:62` |
| `swiftForceUnwrapFAKit` | `CrashTestSite.swift:13` | `CrashTestSite.swift:13` |
| `swiftBackgroundThread` | `CrashTest.swift:68`, non-main | `CrashTest.swift:68`, non-main |
| `kotlinException` | `FACrashReportingBridge.kt:75` | — |
| `appHang` | — | added after this run; not yet run against the server |
| `optOut` | nothing reported | nothing reported |
