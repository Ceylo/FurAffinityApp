#!/bin/bash
#
# Generates the Android-only derived art under FurAffinityUI/Resources/Assets.xcassets
# from the iOS asset catalog, which stays the single source of truth. Nothing this
# script writes is committed — the outputs are git-ignored.
#
# Run it after checking out, and again whenever the iOS art changes. It is idempotent:
# an output newer than its source is left alone.
#
# Why a script rather than a SwiftPM prebuild plugin: `Image(_:bundle:)` resolves
# through this module's asset catalog, so a generated PNG has to land *inside*
# FurAffinityUI/Resources/Assets.xcassets — and the plugin sandbox forbids writing
# back into the source tree.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_catalog="$root/FurAffinity/Assets.xcassets"
dst_catalog="$root/FurAffinityUI/Resources/Assets.xcassets"

# The app icon renders at 100 pt, so 512 px covers xxxhdpi with room to spare —
# a tenth of the size of the 1024×1024 iOS originals.
icon_size=512
src_iconset="$src_catalog/AppIcon.imageset"
dst_iconset="$dst_catalog/AppIcon.imageset"

mkdir -p "$dst_iconset"

resize() {
    local src="$1" dst="$2"
    if [ ! -f "$src" ]; then
        echo "error: missing source image $src" >&2
        exit 1
    fi
    if [ -f "$dst" ] && [ "$dst" -nt "$src" ]; then
        echo "up to date: ${dst#"$root"/}"
        return
    fi
    # -Z preserves the aspect ratio and the alpha channel.
    sips -Z "$icon_size" "$src" --out "$dst" >/dev/null
    echo "generated: ${dst#"$root"/}"
}

resize "$src_iconset/AppIconLG-iOS-Default-1024x1024@1x.png" "$dst_iconset/AppIcon-Light.png"
resize "$src_iconset/AppIconLG-iOS-Dark-1024x1024@1x.png" "$dst_iconset/AppIcon-Dark.png"

# Hand-written rather than copied: the iOS Contents.json points at the original
# filenames, and fills the 3x slot (Skip's asset loader falls back to the highest
# filled scale, so a single 1x entry per appearance is enough here).
cat > "$dst_iconset/Contents.json" <<'JSON'
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
echo "wrote: ${dst_iconset#"$root"/}/Contents.json"
