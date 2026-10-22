#!/bin/bash
set -Eeuo pipefail

export NOVNC_PORT="${NOVNC_PORT:-${PORT:-3000}}"
export VNC_PORT="${VNC_PORT:-5901}"

exec websockify \
    --web=/usr/share/novnc \
    --heartbeat=30 \
    "0.0.0.0:${NOVNC_PORT}" \
    "127.0.0.1:${VNC_PORT}"
