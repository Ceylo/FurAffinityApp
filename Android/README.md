# FurAffinity on Android (Skip Fuse)

The Android app is built from the same SwiftUI source as the iOS app using
[Skip](https://skip.dev) (Fuse / native mode). The iOS app is unchanged: it is
still built by `FurAffinity.xcodeproj` and none of its files move.

## Documentation

| Doc | Covers |
|---|---|
| [docs/build-and-run.md](docs/build-and-run.md) | emulator, build, run, debug, test, and the build-environment traps |
| [docs/shared-sources.md](docs/shared-sources.md) | guarding, and every rule for writing a file both platforms compile |
| [docs/assets-and-resources.md](docs/assets-and-resources.md) | asset-catalog symlinks, generated launcher/app art |
| [docs/forks.md](docs/forks.md) | the four forked dependencies and every patch in them |
| [docs/upstreaming.md](docs/upstreaming.md) | sending a fork patch back to its origin project: gates, evidence, PR shape |
| [docs/images.md](docs/images.md) | the Android image pipeline, the shared HTTP client, and why HTTP/2 does not ship |
| [docs/cloudflare-and-login.md](docs/cloudflare-and-login.md) | login, the long-lived hidden WebView, Cloudflare challenges and how one is repaired |
| [docs/screens.md](docs/screens.md) | Followed feed, submission screen, animation on SkipUI |
| [docs/releasing.md](docs/releasing.md) | update check, release signing, handing a build to testers |

## Layout

```
Package.swift            Skip Fuse app package (Android build only)
Skip.env                 shared app identity (name, version, package)
Android/                 generated Android app shell + Gradle project
Darwin/                  generated iOS bridge project used by `skip` tooling
Project.xcworkspace      workspace `skip` drives
FurAffinity/             ALL app sources — and the Skip target's directory
  Android/                 FurAffinityUIRoot.swift (bridged root view + app
                           delegate), AndroidRootView.swift
  Helper Views/Android/    Compose builds of the shared views, next to their
  Helpers/Android/         iOS/ counterparts — see AGENTS.md §Working Notes
  iOS/                     iOS-only sources + Info.plist, entitlements, icons
  Resources/               the Android asset catalog Skip mirrors
  Skip/skip.yml            marks this a native Skip module
Scripts/Android/         emulator, run, logs, derived art, release APK
Scripts/iOS/             this worktree's simulator device
FAKit/                   shared Swift package (cross-compiles, see AGENTS.md)
```

Skip's transpiler walks that whole tree, so every source the Android build must
not compile is wrapped whole-file in `#if !FA_SKIP_MODULE` — the iOS-only files
*and* the plain-SwiftUI screens that are simply not ported yet. **Porting a
screen is deleting its guard.** See
[docs/shared-sources.md](docs/shared-sources.md#why-everything-unported-is-guarded)
for why it must be that flag and not `os(Android)`.

## Prerequisites

```
skip checkup                        # verifies toolchain (Xcode, Android SDK, Gradle, JDK)
skip android sdk install            # if the Android SDK/NDK is missing
Scripts/Android/generate-assets.sh  # derived art (see docs/assets-and-resources.md)
```

## Quick start

Boot an emulator — nothing in the Skip toolchain does it for you — then build,
run and test. Each command is explained in
[docs/build-and-run.md](docs/build-and-run.md).

```
Scripts/Android/start-emulator.sh  # boots, waits, never touches the app
Scripts/Android/run.sh             # builds, installs, starts this worktree's app
```

Each worktree installs its **own** debug app (its directory name becomes the
`applicationIdSuffix` and the launcher label), which is why running it goes
through that script: `skip app launch --android` installs the same APK and then
starts the *unsuffixed* id. It still has its own use — it is the only command
that compiles the Darwin bridge.

```
skip android build                           # transpile + compile via SwiftPM (fast inner loop)
Scripts/Android/build-release-apk.sh         # the signed release APK (docs/releasing.md)
```

```
Scripts/Android/logs.sh                      # our tags only, live
cd FAKit && skip android test --testing-library testing
xcodebuild test -scheme FurAffinity -destination "id=$(Scripts/iOS/simulator.sh --udid)"
```

The iOS build must stay green at every step; `skip android build` being green
does **not** mean the app still builds, since only `skip app launch` compiles the
Darwin bridge.
