#!/bin/bash
# Pre-approves the package plugins and macros the iOS build runs, as Xcode's
# "Trust & Enable" would, so a fresh CI runner can build without
# -skipPackagePluginValidation. Trust is per revision: each fingerprint is the
# pin in the Xcode project's Package.resolved, so nothing off these lists, and
# no other revision of what is on them, gets approved.
set -euo pipefail

plugins=(skip/skipstone)
macros=(defaults/DefaultsMacrosDeclarations)

root=$(cd "$(dirname "$0")/../.." && pwd)
resolved="$root/FurAffinity.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
security_dir="$HOME/Library/org.swift.swiftpm/security"

trust_list() {
    local entry package target revision
    for entry in "$@"; do
        package=${entry%%/*}
        target=${entry#*/}
        revision=$(jq -er --arg id "$package" '.pins[] | select(.identity == $id) | .state.revision' "$resolved") \
            || { echo "error: $package is not pinned in $resolved" >&2; return 1; }
        jq -n --arg f "$revision" --arg p "$package" --arg t "$target" \
            '{fingerprint: $f, packageIdentity: $p, targetName: $t}'
    done | jq -s .
}

mkdir -p "$security_dir"
trust_list "${plugins[@]}" > "$security_dir/plugins.json"
trust_list "${macros[@]}" > "$security_dir/macros.json"
cat "$security_dir/plugins.json" "$security_dir/macros.json"
