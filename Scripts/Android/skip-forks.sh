# Sourced by the scripts that run Gradle. Builds against local fork checkouts
# rather than their GitHub `android` branches: FA_SKIP_FORKS is the directory
# holding skip, skip-fuse-ui, skip-web and Kingfisher (read by Package.swift and
# FAKit/Package.swift), and SKIPLOCAL a skipstone source checkout, which skip's
# own manifest then builds its plugin from in place of the prebuilt binary.
# Override either per worktree.

export FA_SKIP_FORKS="${FA_SKIP_FORKS:-$HOME/Development/SkipForks/wt/private-state}"
export SKIPLOCAL="${SKIPLOCAL:-$HOME/Development/SkipForks/wt/private-state-mirror/skipstone}"

for dir in "$FA_SKIP_FORKS"/{skip,skip-fuse-ui,skip-web,Kingfisher} "$SKIPLOCAL"; do
    [[ -f "$dir/Package.swift" ]] || { echo "error: no package at $dir" >&2; exit 1; }
done
