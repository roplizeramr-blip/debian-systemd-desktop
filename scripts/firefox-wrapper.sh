#!/bin/bash
set -Eeuo pipefail

# Firefox's full sandbox can fail under some container seccomp profiles.
# The default is to keep the sandbox enabled; set FIREFOX_NO_SANDBOX=1 only
# if Firefox refuses to start and you accept the reduced isolation.
if [ "${FIREFOX_NO_SANDBOX:-0}" = "1" ]; then
    exec /usr/bin/firefox --no-sandbox "$@"
fi
exec /usr/bin/firefox "$@"
