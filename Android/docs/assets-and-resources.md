# Assets and resources

## Sharing asset-catalog entries

`FurAffinity/Resources/Assets.xcassets` is this module's own catalog, which Skip
mirrors into Android resources. Every iOS colorset but `AccentColor` (which SkipUI
would read as the app's tint) is **copied** there by
`Scripts/Android/generate-assets.sh` (see [Generated art](#generated-art)), and the
copy is git-ignored.

Not a symlink, which was the old arrangement: `skip android test` pushes the module's
resource bundle with `adb push`, and adb cannot create a symlink on the device
("remote symlink failed: Permission denied"), so the root package's tests could not
run. A symlinked `.colorset` *directory* was never an option either — Skip's
resource copy silently skips it.

Whatever the mechanism, a missing entry fails quietly: `Color(_:bundle:)` falls back
to an opaque default, so a 10%-alpha border renders as a solid grey one instead of
erroring. After changing a catalog, confirm the entry actually landed:

```
ls -R "$(cat .build/.fa-slot)"/.build/plugins/outputs/*/FurAffinityUI/destination/skipstone/FurAffinityUI/src/main/assets
```

That is the [build slot](build-and-run.md#build-slots) the last Gradle build used; drop
the prefix when slots are off. The path segment after `outputs/` is the **checkout
directory's name** (`android-slot-<n>` in a slot), not the word `android` — hence the
glob.

## Reaching a catalog image from shared code

`Bundle.faAssets` is the bundle a shared view names when it draws an asset-catalog
image or colour, so the view itself needs no `#if`:

```swift
Image("DefaultAvatar", bundle: Bundle.faAssets)
```

It is an ordinary substitution pair — `FurAffinity/Helpers/iOS/AssetBundle.swift`
returns `.main` (an Xcode app target has no `Bundle.module`) and the unguarded
`FurAffinity/Helpers/Android/AssetBundle+Android.swift` returns `.module` (this
module has no `.main` catalog). `AppIcon` and `AvatarView` are single shared files
because of it, and `Colors.swift` spells its colorsets the same way.

Write `Bundle.faAssets`, not the leading-dot `.faAssets`: `Image(_:bundle:)` and
`Color(_:bundle:)` take a `Bundle?`, and implicit member lookup does not reach an
extension member through the optional in the Android build.

An entry a shared view names must exist in **both** catalogs under the same name —
`DefaultAvatar.imageset` is committed on both sides, `AppIcon.imageset` and the
colorsets are committed on iOS and generated on Android (below).

## Generated art

An entry big enough that a second copy in git would hurt, or one that must stay
identical to its iOS original, is generated from the iOS catalog instead, and
git-ignored. `Scripts/Android/generate-assets.sh` writes three sets:

- every colorset but `AccentColor`, `Contents.json` copied verbatim;

- the in-app `AppIcon`, a 512×512 light/dark pair downscaled from two 1024×1024 PNGs
  (the view draws it at 100 pt);
- the launcher icon — `mipmap-*/ic_launcher_foreground.png` at the adaptive layer's
  108 dp and `mipmap-*/ic_launcher.png` at the legacy 48 dp, both from the light art
  (an adaptive icon has no dark variant).

`mipmap-anydpi/ic_launcher.xml` and `values/ic_launcher_background.xml` are
hand-written and committed. The art is a full-bleed rounded square whose subject
touches every edge, so the XML insets the foreground by 16.7% into the 72 dp safe
zone rather than letting a circular launcher mask clip the ears; the background is a
solid colour sampled from the art's yellow field, visible only in the parallax band.
Skip's template `<monochrome>` layer is gone — keeping it would leave Skip's sun as
the themed-icon variant.

The `fa.build-slots` settings plugin runs the script at configuration time (first
thing it does, same `providers.exec` mechanism as `skip plugin --prebuild`),
so a Gradle build or an Android Studio sync regenerates everything. That is the one
place that orders correctly for *both* consumers — the app module's resource merge
and the skipstone included build's resource copy — since an `app:preBuild` task
dependency cannot order against a separate included build. The script is therefore
written to be a true no-op when up to date, content-compared rather than rewritten.

`skip android build` goes through SwiftPM only and never runs Gradle, so it stays a
documented prerequisite; skipping it there costs a blank in-app icon and opaque
default colours. It is
idempotent and takes under a second:

```
Scripts/Android/generate-assets.sh
```

A SwiftPM prebuild plugin would be nicer, but it cannot work: `Image(_:bundle:)`
resolves through this module's catalog **in the source tree**, and the plugin
sandbox forbids writing there.
