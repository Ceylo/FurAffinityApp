#!/bin/bash
#
# Install what a CI Android job needs from Skip, without Homebrew.
#
# Usage: Scripts/Android/ci-setup.sh
#
# skiptools/actions/setup-skip goes through `brew install skip`, whose
# dependencies have no bottles on the Intel macOS 26 runner: swiftly and a JDK's
# openssl built from source took 20 of that job's 27 setup minutes. Only three
# things are needed, and none from Homebrew:
#
#   - swiftly, from swift.org's package — `skip android sdk install` uses it for
#     the host toolchain the Swift Android SDK must match;
#   - the skip CLI at the manifests' pin (check-skip-version.sh --install);
#   - the Swift Android SDK, SWIFT_ANDROID_SDK_VERSION (default 6.3.3).
#
# The JDK comes from actions/setup-java, Gradle from the project's wrapper and the
# Android SDK from the runner image. Exports what later steps need through
# GITHUB_PATH / GITHUB_ENV. See Android/docs/build-and-run.md § CI.

set -eo pipefail

die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -n "$GITHUB_ENV" && -n "$GITHUB_PATH" ]] || die "this sets up a GitHub Actions runner"
TMP="${RUNNER_TEMP:?}"
SDK_VERSION="${SWIFT_ANDROID_SDK_VERSION:-6.3.3}"

step "swiftly"
if ! command -v swiftly >/dev/null; then
    curl -fsSL -o "$TMP/swiftly.pkg" https://download.swift.org/swiftly/darwin/swiftly.pkg
    installer -pkg "$TMP/swiftly.pkg" -target CurrentUserHomeDirectory
    "$HOME/.swiftly/bin/swiftly" init --skip-install --assume-yes --quiet-shell-followup
    # shellcheck disable=SC1091
    . "$HOME/.swiftly/env.sh"
    echo "$HOME/.swiftly/bin" >> "$GITHUB_PATH"
    echo "SWIFTLY_HOME_DIR=$SWIFTLY_HOME_DIR" >> "$GITHUB_ENV"
    echo "SWIFTLY_BIN_DIR=$SWIFTLY_BIN_DIR" >> "$GITHUB_ENV"
    echo "SWIFTLY_TOOLCHAINS_DIR=${SWIFTLY_TOOLCHAINS_DIR:-}" >> "$GITHUB_ENV"
fi
swiftly --version

step "skip"
"$ROOT/Scripts/Android/check-skip-version.sh" --install
# That exported the download to later steps; this script needs it too.
SKIP_BIN="$(tail -1 "$GITHUB_PATH")"
if [[ -x "$SKIP_BIN/skip" ]]; then export PATH="$SKIP_BIN:$PATH"; fi
skip version

step "Swift Android SDK $SDK_VERSION"
# The runner image's Android SDK, whose sdkmanager Homebrew would otherwise provide.
CMDLINE_TOOLS="${ANDROID_HOME:?}/cmdline-tools/latest/bin"
[[ -x "$CMDLINE_TOOLS/sdkmanager" ]] || die "no sdkmanager in $CMDLINE_TOOLS"
export PATH="$CMDLINE_TOOLS:$PATH"
echo "$CMDLINE_TOOLS" >> "$GITHUB_PATH"
skip android sdk install --version "$SDK_VERSION"
# As setup-skip does: a set ANDROID_NDK_ROOT breaks the SDK's NDK lookup
# (finagolfin/swift-android-sdk#207).
echo "ANDROID_NDK_ROOT=" >> "$GITHUB_ENV"
