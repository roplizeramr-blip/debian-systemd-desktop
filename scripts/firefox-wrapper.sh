#!/bin/bash
set -Eeuo pipefail

# Use the pre-seeded profile unless the caller explicitly chose one.  Firefox
# otherwise creates a new "default-release" profile on first start and ignores
# the Arabic user.js that ships with this image.
PROFILE_DIR="${FIREFOX_PROFILE:-${HOME:-/home/desktop}/.mozilla/firefox/desktop.default-release}"

has_profile=0
for arg in "$@"; do
    case "$arg" in
        -profile | --profile | -P | --ProfileManager)
            has_profile=1
            ;;
        -profile=* | --profile=*)
            has_profile=1
            ;;
    esac
done

profile_args=()
if [ "$has_profile" -eq 0 ]; then
    profile_args=(-profile "$PROFILE_DIR")
fi

# Firefox's full sandbox can fail under some container seccomp profiles.
# The default is to keep the sandbox enabled; set FIREFOX_NO_SANDBOX=1 only
# if Firefox refuses to start and you accept the reduced isolation.
if [ "${FIREFOX_NO_SANDBOX:-0}" = "1" ]; then
    exec /usr/bin/firefox "${profile_args[@]}" --no-sandbox "$@"
fi
exec /usr/bin/firefox "${profile_args[@]}" "$@"
