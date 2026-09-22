# Releasing

## Update check

Settings shows the current and latest versions and a "Get …" link, from
`AppInformation.fetch()` against `api.github.com/.../releases/latest` — plain
`URLSession` on both platforms, since that endpoint wants no cookies and sits
behind no Cloudflare. One release feed serves both: tag `1.19` carries the IPA and
the APK, and draft releases are invisible to `releases/latest`, so publishing
stays manual.

`Bundle.main.version` reads 0.0.0 on Android, which would silently invert the
comparison; `FAAppVersion` is what makes it right (see the User-Agent section).

The tab badge reads `model.appInfo.isUpToDate == false` directly, same expression
as iOS. It used to go through a `Model.isUpdateAvailable` mirror, justified by
"Skip's bridge doesn't see changes to a *nested* `@Observable`" — that diagnosis
was wrong. Nesting has nothing to do with it: `AppInformation.swift` imported
`Observation` rather than `SwiftUI`, so the object got the stdlib registrar and
was inert. See [Every `@Observable` needs `SkipAndroidBridge` in
scope](shared-sources.md#every-observable-needs-skipandroidbridge-in-scope). One import fixed the
badge and Settings' "Latest available version" row together, and the mirror is
gone.

## Release signing

The release `signingConfig` in `Android/app/build.gradle.kts` falls back to the
**debug** key when `keystore.properties` is absent, so out of the box
`assembleRelease` emits a debug-signed APK and exits 0. That is unrecoverable
once shipped: everyone who installed it must uninstall before they can take a
properly signed update. A `gradle.taskGraph.whenReady` check now fails any
`assemble/bundle/package/installRelease` task while the file is missing. The debug
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

## Handing a build to testers

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
the changed applicationId invalidates, exports, checks the signing certificate,
and reverts the working tree on the way out (`--keep-stash` leaves it applied,
`--install` pushes the APK to the running device). It refuses to start on a dirty
tree — reverting is `git checkout -- .`, which is only the exact inverse from a
clean one — and finds the stash by *message*, since the stack is shared with
every other worktree. A missing `keystore.jks` is symlinked from whichever
worktree has one.

Two guards it adds over doing it by hand: `CURRENT_PROJECT_VERSION` must be the
value `MARKETING_VERSION` derives, and `project.pbxproj`'s `MARKETING_VERSION`
must agree with `Skip.env`'s. Both are silent-wrong-artifact bugs otherwise.

What it runs:

```
git stash apply <the distribution stash>   # pbxproj id + Amplitude key + Skip.env id
rm -rf .build/plugins/outputs .build/Darwin .build/Android    # applicationId changed
skip export -d .build/release-export --release --android --no-ios --no-export-project --arch aarch64
mv .build/release-export/FurAffinityUI-release.apk out/FurAffinity-<version>-<commit>.apk
```

`--no-ios` because the Skip-generated iOS shell is not this app's iOS release path.
**`--no-export-project` is not optional**: the source-archive step walks the project
directory, and with the export directory inside it that includes its own output —
it recurses until the zip is 1.37 GB and then fails. You do not want the archive
anyway; the Android source is private. `skip export` writes fixed names, so it
exports into `.build/release-export` and only the APK is moved to
`out/FurAffinity-<version>-<commit>.apk` (send this; `<commit>` is HEAD's short
hash, the same as Sentry's `commit` tag). `out/` is never wiped, so earlier APKs
stay, and the script refuses to start if that exact file already exists. The
`.aab` stays behind in `.build/release-export`, since Play is out.

`assembleRelease` puts the same APK at
`.build/Android/app/outputs/apk/release/app-release.apk` — note `.build/`, not
`Android/app/build/`; Skip redirects `buildDir`.

`skip export` never touches adb — it only writes artifacts. To try the exported APK
on a running emulator or device, install it by hand and launch it from the icon:

```
adb install -r -d out/FurAffinity-<version>-<commit>.apk   # or: build-release-apk.sh --install
```

`-d` (allow downgrade) in case an install with a higher versionCode is already
there. A debug build no longer gets in the way: it carries a per-worktree
`applicationIdSuffix` (see [Run](build-and-run.md#run)), so it is a different
package and cannot raise `INSTALL_FAILED_UPDATE_INCOMPATIBLE` against the
release id. Only another *release*-signed install of the same id can, and that
one needs `adb uninstall ceylo.FurAffinity` first, which wipes the FA session
cookies.
The applicationId is `PRODUCT_BUNDLE_IDENTIFIER` (`ceylo.FurAffinity` with the stash
applied), **not** `ANDROID_PACKAGE_NAME` (`fur.affinity.ui`, the module package).
Without the stash it is `Skip.env`'s committed default, `com.example.id1234` — which
is why a plain `skip app launch` build answers to *that* id (see
[Debug](build-and-run.md#debug)) and a stashed release build to `ceylo.FurAffinity`. To
launch from the shell rather than the icon:
`adb shell monkey -p ceylo.FurAffinity -c android.intent.category.LAUNCHER 1`.

Measured 2026-08-16, release, `arm64-v8a`: **94 MB** (95 MB at 1.19). A universal APK with debug
symbols was 436 MB; stripping took it to 249 MB and the ABI filter to 94 MB. The
stripping only works with the NDK installed (`sdkmanager "ndk;28.2.13676358"`) —
without it AGP's `stripReleaseDebugSymbols` silently copies the libraries through.
`lib_FoundationICU.so` stays ~40 MB of the total; that is ICU data, not symbols.

R8 and resource shrinking run clean. The existing `-keep class fur.affinity.ui.**`
already covers every Kotlin bridge reached by name through `AnyDynamicObject`
(`FAAppInfoBridge`, `FAImageFetchBridge`, `FACookieBridge`, `FADefaultsBridge`,
`FAMediaBridge`, `FADefaultsObserver`) — verified present in the release DEX.

What to tell a tester:

- **Android 9 or newer** (minSdk 28), **arm64 only** — a 32-bit-ARM phone will refuse
  to install it. 18+, and it needs a furaffinity.net account.
- Not ported yet: Notes, Notifications, the Profile tab, Explore/search, story (text)
  and audio submissions, and posting comments. Tapping an author or an avatar shows
  "This screen isn't ported to Android yet."
- First launch shows Cloudflare's "Verify you are human" and needs a real tap.
- Crashes and ANRs report themselves to Sentry, symbolicated down to the source
  line (see [crash-reporting.md](crash-reporting.md)); the toggle for that is
  Settings → Advanced → Send crash reports. The application log is *not* sent, so
  for anything that is not a crash — a hang that resolves, a wrong-looking screen
  — Settings → Export Application Logs is still what to ask for.
