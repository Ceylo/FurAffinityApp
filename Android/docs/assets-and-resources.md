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
