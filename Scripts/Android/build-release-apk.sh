#!/bin/bash
#
# Build the signed, distributable release APK.
#
# Wraps the sequence in Android/docs/releasing.md § Handing a build to testers:
# apply the distribution stash (real app id + Amplitude key + Sentry DSN), drop the
# build dirs the changed applicationId invalidates, `skip export`, then check what
# the APK actually got signed with.
#
# Usage: Scripts/Android/build-release-apk.sh [--out DIR] [--install] [--keep-stash]
#
#   --out         export directory, default <worktree>/out (wiped first)
#   --install     adb install -r -d the result on the running device
#   --keep-stash  leave the distribution stash applied in the working tree
#                 (default: revert the working tree to HEAD on exit)
#
# The stash is applied by *message*, never by stash@{0} — the stack is shared
# with every other worktree and another session may be pushing to it.
#
# Environment: ANDROID_HOME / ANDROID_SDK_ROOT, JAVA_HOME, ANDROID_SERIAL, and
# SENTRY_AUTH_TOKEN — the Sentry Gradle plugin uploads the R8 mapping and the
# unstripped Swift .so files during `skip export`, and without them a crash from
# this APK cannot be symbolicated. Required, so a release cannot silently ship
# without symbols.
#
# The DSN comes from the stash, with the app id and the Amplitude key; the build
# refuses to start if the placeholder is still there.

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STASH_MSG="📱For App Store distribution"

OUT="$ROOT/out"
INSTALL=0
KEEP_STASH=0

while (( $# )); do
    case "$1" in
        -h|--help)   sed -n '3,28p' "$0" | cut -c3-; exit 0 ;;
        --out)       OUT="$2"; shift ;;
        --out=*)     OUT="${1#*=}" ;;
        --install)   INSTALL=1 ;;
        --keep-stash) KEEP_STASH=1 ;;
        *)           die "unknown argument: $1" ;;
    esac
    shift
done

cd "$ROOT"

# --- toolchain --------------------------------------------------------------

command -v skip >/dev/null || die "\`skip\` is not on PATH"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
[[ -d "$SDK" ]] || die "no Android SDK at $SDK — set ANDROID_HOME"
export ANDROID_HOME="$SDK"

# macOS ships a `java` stub that errors out, so probe it rather than its existence.
if [[ -z "$JAVA_HOME" ]] && ! java -version >/dev/null 2>&1; then
    JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    [[ -x "$JBR/bin/java" ]] || die "no JDK — set JAVA_HOME (Android Studio's is $JBR)"
    export JAVA_HOME="$JBR"
fi

# Without the NDK, AGP's stripReleaseDebugSymbols silently copies the .so files
# through and the APK comes out ~2.5x too big. Warn rather than fail.
[[ -d "$SDK/ndk" ]] || echo "warning: no NDK in $SDK/ndk — debug symbols will not be stripped" >&2

# --- signing key ------------------------------------------------------------

# Gitignored, so it exists in whichever checkout it was generated in. Link it
# rather than making the user copy the one irreplaceable file in the project.
if [[ ! -f Android/app/keystore.properties ]]; then
    found=""
    while read -r wt; do
        [[ "$wt" == "$ROOT" ]] && continue
        [[ -f "$wt/Android/app/keystore.properties" && -f "$wt/Android/app/keystore.jks" ]] || continue
        found="$wt"; break
    done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')

    [[ -n "$found" ]] || die "Android/app/keystore.properties is missing and no other worktree has one.
    A release build without it would be signed with the DEBUG key, which is
    unrecoverable once shipped. See Android/docs/releasing.md § Release signing."

    echo "linking signing key from $found"
    ln -s "$found/Android/app/keystore.jks" Android/app/keystore.jks
    ln -s "$found/Android/app/keystore.properties" Android/app/keystore.properties
fi

# --- version sanity ---------------------------------------------------------

skip_env() {
    sed -nE "s@^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*@\1@p" Skip.env | awk 'NR == 1'
}

VERSION="$(skip_env MARKETING_VERSION)"
BUILD="$(skip_env CURRENT_PROJECT_VERSION)"
[[ -n "$VERSION" && -n "$BUILD" ]] || die "MARKETING_VERSION / CURRENT_PROJECT_VERSION missing from Skip.env"

# versionCode must never regress, so it is derived: major*10000 + minor*100 + patch.
IFS=. read -r maj min pat <<< "$VERSION"
EXPECTED=$(( 10#${maj:-0} * 10000 + 10#${min:-0} * 100 + 10#${pat:-0} ))
[[ "$BUILD" == "$EXPECTED" ]] \
    || die "Skip.env: CURRENT_PROJECT_VERSION is $BUILD but $VERSION derives $EXPECTED"

XCODE_VERSION="$(sed -nE 's@^[[:space:]]*MARKETING_VERSION = ([^;]+);@\1@p' \
    FurAffinity.xcodeproj/project.pbxproj | awk 'NR == 1')"
[[ "$XCODE_VERSION" == "$VERSION" ]] \
    || die "version mismatch: Skip.env says $VERSION, project.pbxproj says $XCODE_VERSION"

# --- the distribution stash -------------------------------------------------

STASH="$(git stash list --format='%H %gs' | awk -v m="$STASH_MSG" 'f { next } index($0, m) { print $1; f = 1 }')"
[[ -n "$STASH" ]] || die "no stash whose message contains \"$STASH_MSG\" — it carries the
    real app id and the Amplitude key, and without it this builds com.example.id1234."

# The stash is applied into the working tree and reverted afterwards, so the
# tree has to start clean: that is what makes `git checkout -- .` the exact
# inverse. Matching the stash's own paths instead would not be — it still names
# FurAffinity/Secrets.swift, and rename detection lands it on FurAffinity/iOS/.
DIRTY="$(git status --porcelain --untracked-files=no)"
[[ -z "$DIRTY" ]] || die "the working tree has uncommitted changes — commit them first.
$DIRTY"

restore() {
    if (( KEEP_STASH )); then
        echo; echo "distribution stash left applied (--keep-stash)"
    else
        git -C "$ROOT" checkout -- .
    fi
}
# EXIT alone would not fire on a Ctrl-C or a kill, leaving the Amplitude key in
# the working tree.
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

step "Applying \"$STASH_MSG\" ($(git rev-parse --short "$STASH"))"
git stash apply "$STASH"

APP_ID="$(skip_env ANDROID_APPLICATION_ID)"
[[ -n "$APP_ID" ]] || APP_ID="$(skip_env PRODUCT_BUNDLE_IDENTIFIER)"
echo "app id $APP_ID, version $VERSION ($BUILD)"

# Both halves of crash reporting, checked after the stash is applied: it is what
# carries the DSN. See Android/docs/crash-reporting.md.
[[ -n "$SENTRY_AUTH_TOKEN" ]] \
    || die "SENTRY_AUTH_TOKEN is not set — the build would upload no symbols, and
    crashes from this APK could not be symbolicated. Export it (the org auth token,
    project:releases scope) and rerun."
grep -qE 'static let dsn = "(Your Sentry DSN)?"' "$ROOT/FurAffinity/CrashReportingSecrets.swift" \
    && die "no Sentry DSN — this APK would report no crashes at all. Add it to
    \"$STASH_MSG\" and rerun."

# --- build ------------------------------------------------------------------

# The applicationId just changed, and these three cache it.
step "Clearing .build/{plugins/outputs,Darwin,Android} and $OUT"
rm -rf .build/plugins/outputs .build/Darwin .build/Android "$OUT"

# --no-ios: the Skip-generated iOS shell is not this app's iOS release path.
# --no-export-project: the source-archive step walks the project directory, and
# with the output folder inside it that recurses until the zip is >1 GB and fails.
step "skip export"
skip export -d "$OUT" --release --android --no-ios --no-export-project

APK="$OUT/FurAffinityUI-release.apk"
[[ -f "$APK" ]] || die "skip export produced no $APK"

# --- verify the signature ---------------------------------------------------

APKSIGNER="$(ls -d "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
if [[ -x "$APKSIGNER" ]]; then
    step "Signing certificate"
    CERTS="$("$APKSIGNER" verify --print-certs "$APK")"
    echo "$CERTS"
    if grep -q "CN=Android Debug" <<< "$CERTS"; then
        die "the APK is DEBUG-signed — do not ship it. See Android/docs/releasing.md § Release signing."
    fi
else
    echo "warning: no apksigner in $SDK/build-tools — signature unverified" >&2
fi

# --- done -------------------------------------------------------------------

step "$APK"
ls -lh "$APK" | awk '{ print $5 }'

if (( INSTALL )); then
    step "Installing on the device"
    # -d allows the downgrade when a higher versionCode is already installed.
    "$(dirname "${BASH_SOURCE[0]}")/with-emulator-lock.sh" \
        "$SDK/platform-tools/adb" install -r -d "$APK"
    echo "launch it from the icon, or:"
    echo "  adb shell monkey -p $APP_ID -c android.intent.category.LAUNCHER 1"
fi
