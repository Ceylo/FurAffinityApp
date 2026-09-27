#!/bin/bash
#
# Keep Gradle's local build cache under a size cap, least recently used first.
#
# The cache is shared by every worktree (Android/gradle.properties), and Gradle
# only expires entries by age (7 days unused), not by size. settings.gradle.kts
# runs this before the build writes anything, so it prunes to the cap minus one
# build's writes.
#
# Reading an entry moves its atime (on APFS at most once a day), so atime order
# is LRU order to the day. Deleting an entry another worktree is about to read is
# only a miss.
#
# Environment: GRADLE_USER_HOME (default ~/.gradle), FA_BUILD_CACHE_CAP_KB (to
# override the cap, e.g. to test the prune).

set -euo pipefail

# 1.5 × a clean debug build's .build (3,694,692 KB, 2026-09-26), and what one
# clean debug build writes into an empty cache (41,072 KB, same day).
CAP_KB="${FA_BUILD_CACHE_CAP_KB:-5542038}"
BUILD_WRITES_KB=41072

cache="${GRADLE_USER_HOME:-$HOME/.gradle}/caches/build-cache-1"
[[ -d "$cache" ]] || exit 0

# Entries are the hash-named files; leave the lock and gc.properties alone.
# stat's %b counts 512-byte blocks, so halving it gives `du -k`'s unit.
find "$cache" -maxdepth 1 -ignore_readdir_race -type f ! -name '*.lock' ! -name 'gc.properties' -print0 \
    | { xargs -0 stat -f '%a %b %N' 2>/dev/null || true; } \
    | sort -n \
    | awk -v target=$(( CAP_KB - BUILD_WRITES_KB )) '
        { kb[NR] = $2 / 2; total += kb[NR]
          sub(/^[0-9]+ [0-9]+ /, ""); path[NR] = $0 }
        END {
            for (i = 1; i <= NR && total > target; i++) {
                print path[i]; total -= kb[i]; freed += kb[i]; n++
            }
            if (n) printf "build cache: pruned %d entries, %d MB\n", n, freed / 1024 > "/dev/stderr"
        }' \
    | tr '\n' '\0' \
    | xargs -0 rm -f
