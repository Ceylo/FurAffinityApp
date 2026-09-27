#!/bin/bash
#
# Install or refresh the "FA Compilation Cache" toolchain, which lets every
# worktree reuse the others' Debug compiles from Xcode's compilation cache.
#
# The cache keys a compile on its inputs' paths, and those differ per worktree:
# the checkout, and its DerivedData directory, which also holds the package
# checkouts. The toolchain maps both to placeholders (/^src, /^derived) through
# OverrideBuildSettings — the only settings that reach package targets — and its
# swift-frontend (Scripts/iOS/compilation-cache-swift-frontend) maps what Xcode
# 26.6's driver still leaves unmapped. It is an APFS clone of Xcode's default
# toolchain, so it costs no disk. See COMPILATION_CACHE.md.
#
# Usage: Scripts/iOS/compilation-cache-toolchain.sh [--if-stale]
#
#   --if-stale   do nothing unless it is missing, or was made from another Xcode
#                or another shim; the scheme's build pre-action runs this
#
# Select it in Xcode ▸ Toolchains, or with TOOLCHAINS=dev.fa.compilation-cache
# for xcodebuild. Remove it by deleting the directory printed below.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM="$HERE/compilation-cache-swift-frontend"
ID=dev.fa.compilation-cache
DST="$HOME/Library/Developer/Toolchains/FACompilationCache.xctoolchain"

IF_STALE=0
case "${1:-}" in
    -h|--help)  sed -n '3,20p' "$0" | cut -c3-; exit 0 ;;
    --if-stale) IF_STALE=1 ;;
    "")         ;;
    *)          die "unknown option $1 (see --help)" ;;
esac

DEV="$(xcode-select -p)"
SRC="$DEV/Toolchains/XcodeDefault.xctoolchain"
[[ -d "$SRC" ]] || die "no default toolchain in $DEV"
XCODE_BUILD="$(plutil -extract ProductBuildVersion raw "$DEV/../version.plist")"
STAMP="$XCODE_BUILD $(md5 -q "$SHIM")"

if (( IF_STALE )) && [[ "$(plutil -extract FAStamp raw "$DST/Info.plist" 2>/dev/null)" == "$STAMP" ]]; then
    exit 0
fi

# Built aside and swapped in whole, so a build running meanwhile keeps a
# consistent toolchain.
TMP="$DST.new.$$"
OLD="$DST.old.$$"
trap 'rm -rf "${TMP:?}" "${OLD:?}"' EXIT
mkdir -p "${DST%/*}"
cp -Rc "$SRC" "$TMP"
rm "$TMP/ToolchainInfo.plist"   # carries Xcode's own toolchain identifier

# A tool whose rpath climbs out of the toolchain into Xcode.app finds nothing from
# here. dyld resolves @executable_path through symlinks, so point back at Xcode's.
while IFS= read -r file; do
    otool -l "$file" 2>/dev/null | grep -A2 LC_RPATH | grep -q ' path .*\.\./\.\./\.\./\.\.' || continue
    rel="${file#"$TMP"/}"
    [[ "$rel" == *.framework/* ]] && rel="${rel%%.framework/*}.framework"
    [[ -L "$TMP/$rel" ]] && continue
    rm -rf "${TMP:?}/${rel:?}"
    ln -s "$SRC/$rel" "$TMP/$rel"
done < <(find "$TMP/usr" -type f -perm -u+x)

mv "$TMP/usr/bin/swift-frontend" "$TMP/usr/bin/swift-frontend-real"
cp "$SHIM" "$TMP/usr/bin/swift-frontend"
chmod +x "$TMP/usr/bin/swift-frontend"

# /^src is the workspace's parent directory: the checkout, whichever of its
# workspaces is open. /^derived is this build's DerivedData directory.
MAPS='$(FA_CAS_WORKTREE:standardizepath)=/^src $(FA_CAS_DERIVED_DATA:standardizepath)=/^derived'
cat > "$TMP/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>$ID</string>
	<key>CompatibilityVersion</key>
	<integer>2</integer>
	<key>DisplayName</key>
	<string>FA Compilation Cache (Xcode $XCODE_BUILD)</string>
	<key>ShortDisplayName</key>
	<string>FA Compilation Cache</string>
	<key>Version</key>
	<string>1.0.0</string>
	<key>FAStamp</key>
	<string>$STAMP</string>
	<key>OverrideBuildSettings</key>
	<dict>
		<key>FA_CAS_WORKTREE</key>
		<string>\$(WORKSPACE_DIR)/..</string>
		<key>FA_CAS_DERIVED_DATA</key>
		<string>\$(OBJROOT)/../..</string>
		<key>SWIFT_ENABLE_PREFIX_MAPPING</key>
		<string>YES</string>
		<key>SWIFT_OTHER_PREFIX_MAPPINGS</key>
		<string>$MAPS</string>
		<key>CLANG_ENABLE_PREFIX_MAPPING</key>
		<string>YES</string>
		<key>CLANG_OTHER_PREFIX_MAPPINGS</key>
		<string>$MAPS</string>
	</dict>
</dict>
</plist>
EOF
plutil -lint -s "$TMP/Info.plist"


# A concurrent install from another worktree may have already rotated $DST out
# from under this check by the time the mv below runs; that's fine, both installs
# converge on the same toolchain either way.
mv "$DST" "$OLD" 2>/dev/null || true
mv "$TMP" "$DST"
echo "installed $DST (Xcode $XCODE_BUILD)"
