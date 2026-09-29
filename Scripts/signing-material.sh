# Sourced by Scripts/Android/slot-sync.sh, which never copies these files, and
# Scripts/cleanup-worktree.sh, which won't remove a worktree holding them:
# keystores, certificates, profiles and the Sentry token.
# shellcheck shell=bash
is_signing_material() {
    case "${1##*/}" in
        *.p12|*.mobileprovision|*.jks|*.keystore|keystore.properties|.sentryclirc) return 0 ;;
    esac
    return 1
}
