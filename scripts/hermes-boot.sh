#!/bin/bash
# Point Hermes Agent at the DeepSeek API at container start.
#
# The CLI, its pinned toolchain and the DeepSeek provider selection are baked
# into the image (see the Dockerfile).  Only the API key is deployment-specific,
# so it arrives in the environment as DEEPSEEK_API_KEY and is written into the
# desktop account's ~/.hermes/.env here -- the same place
# `hermes config set DEEPSEEK_API_KEY` writes, and no secret ends up in the
# image or the repository.
#
# Supervisord runs this once, as the desktop user.  It is best effort: a missing
# key, a missing CLI or a failed write must never keep the desktop from coming
# up.

set -u

export HOME="${HOME:-/home/desktop}"

HERMES_CLI="${HOME}/.local/bin/hermes"

log() { printf '[hermes-boot] %s\n' "$*"; }

if [ ! -x "$HERMES_CLI" ]; then
    log "Hermes is not installed; nothing to do"
    exit 0
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
    log "DEEPSEEK_API_KEY is unset; leaving the Hermes credentials alone"
    exit 0
fi

if "$HERMES_CLI" config set DEEPSEEK_API_KEY "$DEEPSEEK_API_KEY" >/dev/null 2>&1; then
    log "DeepSeek API key applied"
else
    log "could not apply the key; run 'hermes config set DEEPSEEK_API_KEY ...' in a terminal"
fi

exit 0
