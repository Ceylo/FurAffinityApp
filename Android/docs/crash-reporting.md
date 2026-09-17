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
  The real DSN is never committed and is not in the distribution stash either: CI
  and the Android release script write it in for the build and revert it after.
  Both need `SENTRY_DSN`; the uploads additionally need `SENTRY_AUTH_TOKEN`, which
  is the only real secret of the two — the DSN can merely *send* events to this
  project, while the token reads and administers it.
- `CrashReporting.start` is the first thing both entry points do — on Android right
  after `installDefaultsSuite()`, since it reads a `Defaults` key.

Collected: stack trace, device model, OS and app version, and the SDK's random
per-install id. Not collected: `sendDefaultPii` is off, no screenshots, no view
hierarchy, no tracing, no network breadcrumbs, and no application log (see
§ No breadcrumbs).

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
| The DSN | `sed` from `$SENTRY_DSN` into `CrashReportingSecrets.swift` — `.github/workflows/{build,release}.yml` on iOS, `Scripts/Android/build-release-apk.sh` on Android, reverted after the build | every distributed build |
| iOS dSYMs (+ sources) | `sentry-cli debug-files upload --include-sources` in `.github/workflows/release.yml` | every tagged release |
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

Kotlin frames have line numbers but **no source text** — the Gradle plugin
registers no source-bundle task here, so `includeSourceContext` has no effect.
Swift frames do carry source text, from `--include-sources`.

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
