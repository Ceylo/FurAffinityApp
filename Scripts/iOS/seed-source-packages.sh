#!/bin/bash
# Kept for post-checkout hooks installed before seed-source-packages.py replaced
# this script: they run it by this name. Re-running Scripts/install-git-hooks.sh
# installs a hook that calls the .py directly.
exec "$(dirname "${BASH_SOURCE[0]}")/seed-source-packages.py" "$@"
