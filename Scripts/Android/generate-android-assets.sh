#!/bin/bash
#
# Generates the Android-only derived art from the iOS asset catalog, which stays the
# single source of truth:
#
#   - FurAffinityUI/Resources/Assets.xcassets/AppIcon.imageset — the in-app icon
#   - Android/app/src/main/res/mipmap-* — the launcher icon
#
# Nothing this script writes is committed — the outputs are git-ignored.
#
# Android/settings.gradle.kts runs it at configuration time, so a Gradle build or an
# Android Studio sync regenerates it automatically. `skip android build` goes through
# SwiftPM only and does not, hence run it by hand after checking out. It is idempotent:
# an output newer than its source, or a file whose content is unchanged, is left alone.
#
# Why a script rather than a SwiftPM prebuild plugin: `Image(_:bundle:)` resolves
# through this module's asset catalog, so a generated PNG has to land *inside*
# FurAffinityUI/Resources/Assets.xcassets — and the plugin sandbox forbids writing
# back into the source tree.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src_catalog="$root/FurAffinity/Assets.xcassets"
dst_catalog="$root/FurAffinityUI/Resources/Assets.xcassets"
android_res="$root/Android/app/src/main/res"

src_iconset="$src_catalog/AppIcon.imageset"
dst_iconset="$dst_catalog/AppIcon.imageset"
src_icon_light="$src_iconset/AppIconLG-iOS-Default-1024x1024@1x.png"
src_icon_dark="$src_iconset/AppIconLG-iOS-Dark-1024x1024@1x.png"

resize() {
    local size="$1" src="$2" dst="$3"
    if [ ! -f "$src" ]; then
        echo "error: missing source image $src" >&2
        exit 1
    fi
    if [ -f "$dst" ] && [ "$dst" -nt "$src" ]; then
        echo "up to date: ${dst#"$root"/}"
        return
    fi
    # -Z preserves the aspect ratio and the alpha channel.
    sips -Z "$size" "$src" --out "$dst" >/dev/null
    echo "generated: ${dst#"$root"/}"
}

# Writes stdin to $1, but only if the content differs — the script runs on every Gradle
# configuration, and an unconditional write would touch the mtime each time.
write_if_changed() {
    local dst="$1" tmp="$1.tmp"
    cat > "$tmp"
    if [ -f "$dst" ] && cmp -s "$tmp" "$dst"; then
        rm -f "$tmp"
        echo "up to date: ${dst#"$root"/}"
        return
    fi
    chmod 644 "$tmp"
    mv "$tmp" "$dst"
    echo "wrote: ${dst#"$root"/}"
}

# MARK: - In-app icon

# The app icon renders at 100 pt, so 512 px covers xxxhdpi with room to spare —
# a tenth of the size of the 1024×1024 iOS originals.
mkdir -p "$dst_iconset"
resize 512 "$src_icon_light" "$dst_iconset/AppIcon-Light.png"
resize 512 "$src_icon_dark" "$dst_iconset/AppIcon-Dark.png"

# Hand-written rather than copied: the iOS Contents.json points at the original
# filenames, and fills the 3x slot (Skip's asset loader falls back to the highest
# filled scale, so a single 1x entry per appearance is enough here).
write_if_changed "$dst_iconset/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "AppIcon-Light.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-Dark.png",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

# MARK: - Launcher icon

# Only the light art: an adaptive icon has no dark variant.
#
# The foreground layer is 108 dp — mipmap-anydpi/ic_launcher.xml insets it into the
# 72 dp safe zone, since the art is a full-bleed rounded square whose subject touches
# every edge and a circular launcher mask would clip it. The legacy icon is 48 dp; it
# goes unused at minSdk 28, but android:icon still has to resolve it.
densities=(mdpi hdpi xhdpi xxhdpi xxxhdpi)
foreground_sizes=(108 162 216 324 432)
legacy_sizes=(48 72 96 144 192)

for i in "${!densities[@]}"; do
    dir="$android_res/mipmap-${densities[$i]}"
    mkdir -p "$dir"
    resize "${foreground_sizes[$i]}" "$src_icon_light" "$dir/ic_launcher_foreground.png"
    resize "${legacy_sizes[$i]}" "$src_icon_light" "$dir/ic_launcher.png"
done
