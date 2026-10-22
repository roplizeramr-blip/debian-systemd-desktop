#!/bin/bash
set -Eeuo pipefail

PORT_TO_CHECK="${NOVNC_PORT:-${PORT:-3000}}"
curl -fsS --max-time 5 "http://127.0.0.1:${PORT_TO_CHECK}/healthz" >/dev/null
