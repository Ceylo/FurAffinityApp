# Releasing

## Update check

Settings shows the current and latest versions and a "Get …" link, from
`AppInformation.fetch()` against `api.github.com/.../releases/latest` — plain
`URLSession` on both platforms, since that endpoint wants no cookies and sits
behind no Cloudflare. One release feed serves both: tag `1.19` carries the IPA and
the APK, and draft releases are invisible to `releases/latest`, so publishing
stays manual.

`Bundle.main.version` reads 0.0.0 on Android, which would silently invert the
comparison; `FAAppVersion` is what makes it right (see [cloudflare-and-login.md § The WebView
User-Agent](cloudflare-and-login.md#the-webview-user-agent-carries-the-app-identifier)).

The tab badge reads `model.appInfo.isUpToDate == false` directly, as on iOS. A
nested `@Observable` is fine on Android; what once broke the badge was
`AppInformation.swift` importing `Observation` rather than `SwiftUI` (see [Every
`@Observable` needs `SkipAndroidBridge` in
scope](shared-sources.md#every-observable-needs-skipandroidbridge-in-scope)).

## Release signing

The release `signingConfig` in `Android/app/build.gradle.kts` falls back to the
**debug** key when `keystore.properties` is absent, so out of the box
`assembleRelease` emits a debug-signed APK and exits 0. That is unrecoverable
once shipped: everyone who installed it must uninstall before they can take a
properly signed update. So `preReleaseBuild` and every `package*Release` task fail
while the file is missing. The debug
variant is unaffected, and configuring the project without a keystore still works.

Both files live beside the module (`storeFile` resolves relative to
`Android/app/`) and are git-ignored:

```
keytool -genkeypair -v \
  -keystore Android/app/keystore.jks -alias furaffinity \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Ceylo, O=Ceylo, C=FR"
```

```properties
# Android/app/keystore.properties
storeFile=keystore.jks
storePassword=…
keyAlias=furaffinity
keyPassword=…
```

**Back `keystore.jks` up off-machine before building anything with it.** Losing it
permanently ends the upgrade path for every installed user, and Google's developer
verification (sideloading included, from late 2026) registers a package name bound
to this certificate — neither can be changed afterwards.

Check what a build actually got signed with:

```
apksigner verify --print-certs <apk>      # must NOT say CN=Android Debug
```

## The published APK

The APK on a GitHub release comes from the tag, like the IPA: `release.yml`'s
`android` job seds the app id, the Amplitude key and the DSN in from the same secrets
the IPA job uses, decodes the signing key from two more, and runs
`build-release-apk.sh --ci`. The draft release waits for both jobs. Running the
workflow on a branch (`gh workflow run release.yml --ref <branch>`) builds and checks
both artifacts and uploads their symbols, but drafts no release — a dry run.

`--ci` means the tree already holds the distribution values: no stash, no clean-tree
check, nothing reverted. It also refuses what a local build only warns about or
works around — a missing NDK, and a missing `keystore.properties` (which a local run
borrows from another worktree). Both modes refuse the placeholder app id.

The two signing secrets hold the one irreplaceable file, so they are set by hand,
from the checkout that has it:

```
base64 -i Android/app/keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PROPERTIES < Android/app/keystore.properties
```

The job runs on arm64 `macos-26`, which GitHub has not scheduled for retirement.
If the release SkipUI compile ever runs out of memory there (7 GB, against
`kotlin.daemon.jvmargs=-Xmx4g`), `macos-26-intel` has 14 GB, until August 2027.

## Handing a build to testers

For a build between releases, the same script runs locally:

```
Scripts/Android/build-release-apk.sh
```

It needs a Sentry auth token (the Gradle plugin uploads the `.so` files and the
R8 mapping with it) — `SENTRY_AUTH_TOKEN`, or else `token=` under `[auth]` in the
checkout's `.sentryclirc` or `~/.sentryclirc` — and a DSN, which comes from the stash;
it refuses to build without either. See
[crash-reporting.md](crash-reporting.md) § Releasing, which also covers the two
iOS channels.

That is the whole thing: it applies the distribution stash, drops the build dirs
the changed applicationId invalidates, builds, checks the signing certificate,
and reverts the working tree on the way out (`--keep-stash` leaves it applied,
`--install` pushes the APK to the running device). It refuses to start on a dirty
tree — reverting is `git checkout -- .`, which is only the exact inverse from a
clean one — and finds the stash by *message*, since the stack is shared with
every other worktree. A missing `keystore.jks` is symlinked from whichever
worktree has one.

Two guards it adds over doing it by hand: `CURRENT_PROJECT_VERSION` must be the
value `MARKETING_VERSION` derives, and `project.pbxproj`'s `MARKETING_VERSION`
must agree with `Skip.env`'s. Both are silent-wrong-artifact bugs otherwise.

It builds with `:app:assembleRelease` in the worktree (`FA_ANDROID_SLOTS=0`), not
`skip export`, which builds everything twice in parallel plus an unused `.aab`: 275 s
against 339 s for a byte-identical file list. `SKIP_EXPORT_ARCHS=aarch64` keeps it to
the one ABI the release `abiFilters` ships (that alone took 703 s to 339 s).

`assembleRelease` writes `.build/Android/app/outputs/apk/release/app-release.apk`
— note `.build/`, not `Android/app/build/`; Skip redirects `buildDir` — and the
script moves it to `out/FurAffinity-<version>-<commit>.apk` (send this;
`<commit>` is HEAD's short hash, the same as Sentry's `commit` tag). `out/` is
never wiped, so earlier APKs stay, and the script refuses to start if that exact
file already exists.

The build never touches adb unless asked. To try the APK on a running emulator or
device:

```
Scripts/Android/install-apk.sh --start out/FurAffinity-<version>-<commit>.apk   # or: build-release-apk.sh --install
```

It reinstalls with `adb install -r -d`, keeping the app's data. A debug build never
gets in the way, being a different package (see [Run](build-and-run.md#run)); only an
install of the same id signed with another key can, and the way out, `adb uninstall
ceylo.FurAffinity`, wipes the FA login, so the script leaves that to you.
The applicationId is `PRODUCT_BUNDLE_IDENTIFIER` (`ceylo.FurAffinity` with the stash
applied), **not** `ANDROID_PACKAGE_NAME` (`fur.affinity.ui`, the module package).
Without the stash it is `Skip.env`'s committed default, `com.example.id1234`, which a
debug build suffixes (see [Debug](build-and-run.md#debug)).

Measured 2026-08-16, release, `arm64-v8a`: **94 MB** (108 MB at 1.19, with Skip 1.9.11 and Amplitude). A universal APK with debug
symbols was 436 MB; stripping took it to 249 MB and the ABI filter to 94 MB. The
stripping only works with the NDK installed (`sdkmanager "ndk;28.2.13676358"`) —
without it AGP's `stripReleaseDebugSymbols` silently copies the libraries through.
`lib_FoundationICU.so` stays ~40 MB of the total; that is ICU data, not symbols.

R8 and resource shrinking run clean. The existing `-keep class fur.affinity.ui.**`
already covers every Kotlin bridge reached by name through `AnyDynamicObject`
(`FAAppInfoBridge`, `FAImageFetchBridge`, `FACookieBridge`, `FADefaultsBridge`,
`FAMediaBridge`, `FADefaultsObserver`, `FAAnalyticsBridge`) — verified present in
the release DEX. The Amplitude SDK needed no rule of ours: its AAR carries its own.

What to tell a tester:

- **Android 9 or newer** (minSdk 28), **arm64 only** — a 32-bit-ARM phone will refuse
  to install it. 18+, and it needs a furaffinity.net account.
- Not ported yet: Notes and Explore/search. Music plays in another app rather than
  in-app, and a story opens in-app only as txt or md.
- First launch shows Cloudflare's "Verify you are human" and needs a real tap.
- Crashes and ANRs report themselves to Sentry, symbolicated down to the source
  line (see [crash-reporting.md](crash-reporting.md)); the toggle for that is
  Settings → Advanced → Send crash reports. The application log is *not* sent, so
  for anything that is not a crash — a hang that resolves, a wrong-looking screen
  — Settings → Export Application Logs is still what to ask for.
