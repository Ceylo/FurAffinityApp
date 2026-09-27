#!/bin/bash
#
# Upkeep of the compilation cache, run by the FurAffinity scheme before each build.
#
# COMPILATION_CACHE_LIMIT_SIZE makes Xcode start a new CAS generation once the
# current one outgrows it, but xcodebuild never deletes the generation before
# last, so this does. Also refreshes the FA Compilation Cache toolchain after an
# Xcode update, when it is installed, and drops the shim's scratch files unused
# for 30 days. See COMPILATION_CACHE.md.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$HERE/compilation-cache-toolchain.sh" --if-installed

CAS="${COMPILATION_CACHE_CAS_PATH:-$HOME/Library/Developer/Xcode/DerivedData/CompilationCache.noindex}/builtin"
[[ -d "$CAS" ]] && xcrun llvm-cas --cas="$CAS" --prune

SCRATCH="$HOME/Library/Caches/FACompilationCache"
[[ -d "$SCRATCH" ]] && find "$SCRATCH" -type f -atime +30 -delete

exit 0
