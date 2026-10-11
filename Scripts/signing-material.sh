# Sourced by Scripts/Android/slot-sync.sh, which never copies these files:
# keystores, certificates, profiles and the Sentry token. Twin of
# is_signing_material in Scripts/cleanup-worktree.py, which won't remove a
# worktree holding them: keep the two in step.
# shellcheck shell=bash
is_signing_material() {
    case "${1##*/}" in
        *.p12|*.mobileprovision|*.jks|*.keystore|keystore.properties|.sentryclirc) return 0 ;;
    esac
    return 1
}
