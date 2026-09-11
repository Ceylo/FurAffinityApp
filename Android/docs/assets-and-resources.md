# Assets and resources

## Sharing asset-catalog entries

`FurAffinity/Resources/Assets.xcassets` is this module's own catalog, which Skip
mirrors into Android resources. To single-source an entry with the iOS catalog,
symlink the **`Contents.json`**, not the `.colorset`/`.imageset` directory:

```
mkdir Foo.colorset
ln -s ../../../Assets.xcassets/Foo.colorset/Contents.json Foo.colorset/Contents.json
```

Skip's resource copy does not follow a symlinked *directory* — it silently copies
nothing, and the entry never reaches the APK. The failure is quiet: `Color(_:bundle:)`
falls back to an opaque default, so a 10%-alpha border renders as a solid grey one
instead of erroring. After changing a catalog, confirm the entry actually landed
(the mirrored tree is itself made of symlinks, so `find -type f` won't list them):

```
ls -R .build/plugins/outputs/*/FurAffinityUI/destination/skipstone/FurAffinityUI/src/main/assets
```

The path segment after `outputs/` is the **checkout directory's name**, not the word
`android` — it differs per worktree, hence the glob.

Each build prints two `unable to remove entry
…/{Border,ButtonBorder}Overlay.colorset/Contents.json` warnings. Both name the
**committed symlink**, in the source tree: skipstone wants to replace the entry it
mirrors, and removing it would mean writing to `FurAffinity/Resources/`, which the
SwiftPM plugin sandbox makes read-only (`NSCocoaErrorDomain Code=513`). The link is
already there and still resolves, and the colours reach the APK — the warning is the
sandbox doing its job. The symlinks stay.

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
`DefaultAvatar.imageset` is committed on both sides, `AppIcon.imageset` is committed
on iOS and generated on Android (below).

## Generated art

An entry big enough that a second copy in git would hurt is generated from the iOS
art instead, and git-ignored. `Scripts/Android/generate-assets.sh` writes two sets:

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

`Android/settings.gradle.kts` runs the script at configuration time (first statement
in `pluginManagement`, same `providers.exec` mechanism as `skip plugin --prebuild`),
so a Gradle build or an Android Studio sync regenerates everything. That is the one
place that orders correctly for *both* consumers — the app module's resource merge
and the skipstone included build's resource copy — since an `app:preBuild` task
dependency cannot order against a separate included build. The script is therefore
written to be a true no-op when up to date, content-compared rather than rewritten.

`skip android build` goes through SwiftPM only and never runs Gradle, so it stays a
documented prerequisite; skipping it there costs a blank in-app icon. It is
idempotent and takes under a second:

```
Scripts/Android/generate-assets.sh
```

A SwiftPM prebuild plugin would be nicer, but it cannot work: `Image(_:bundle:)`
resolves through this module's catalog **in the source tree**, and the plugin
sandbox forbids writing there.
