#!/bin/bash
#
# Update the root Package.resolved — e.g. to take a fork's new `android` head.
#
# Runs `swift package update` as an Android resolve: swift-syntax is used only by
# skip-fuse-ui's Android-only `#Preview` macro target, so a Darwin update prunes
# its pin and the next Android build writes it back. Never use this for the Xcode
# project's Package.resolved: the variable would give the iOS graph skip-fuse-ui's
# shim module named `SwiftUI`.
#
# Usage: Scripts/Android/update-packages.sh [package…]   (none: update them all)
#
# Commit the resulting Package.resolved diff — see Android/docs/forks.md.

set -eo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
TARGET_OS_ANDROID=1 exec swift package update "$@"
