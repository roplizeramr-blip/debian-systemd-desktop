#!/bin/bash
# Persistent Tailscale Serve base rule:
#   tailnet TCP :3000 -> 127.0.0.1:6080 (KasmVNC HTTP/WebSocket)
#   optional TLS-terminated :3443 -> the same local socket
#
# This is a raw TCP forwarder, not an HTTP reverse proxy.  That matters for
# KasmVNC: its WebSocket remains end-to-end and does not suffer from proxy
# reconnect/timeout behavior.  The controller exposes the URL and only enables
# "Open VNC" after the corresponding serve rule is active.
set -uo pipefail

KASM_PORT="${KASM_PORT:-6080}"
HTTP_PORT="${TS_SERVE_HTTP_PORT:-3000}"
HTTPS_PORT="${TS_SERVE_HTTPS_PORT:-0}"
INTERVAL="${TS_SERVE_INTERVAL:-10}"

HTTP_FLAG="/run/desktop-tailscale-http.ok"
HTTPS_FLAG="/run/desktop-tailscale-https.ok"

log() {
    printf '[tailscale-serve] %s\n' "$*"
}

backend_state() {
    tailscale status --json 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("BackendState", ""))
except Exception:
    print("")
' 2>/dev/null || true
}

serve_status() {
    tailscale serve status 2>/dev/null || true
}

while true; do
    state="$(backend_state)"
    if [ "$state" != "Running" ]; then
        rm -f "$HTTP_FLAG" "$HTTPS_FLAG"
        sleep "$INTERVAL"
        continue
    fi

    current="$(serve_status)"

    # A flag is only trusted while the corresponding rule is still present.
    # This also recovers if tailscaled restarts with an empty Serve config.
    if [ -f "$HTTP_FLAG" ] && ! printf '%s\n' "$current" | grep -q ":${HTTP_PORT}\b"; then
        rm -f "$HTTP_FLAG"
    fi
    if [ -f "$HTTPS_FLAG" ] && ! printf '%s\n' "$current" | grep -q ":${HTTPS_PORT}\b"; then
        rm -f "$HTTPS_FLAG"
    fi

    if [ ! -f "$HTTP_FLAG" ]; then
        if printf '%s\n' "$current" | grep -q ":${HTTP_PORT}\b"; then
            touch "$HTTP_FLAG"
        elif tailscale serve --bg --tcp="$HTTP_PORT" "tcp://127.0.0.1:${KASM_PORT}"; then
            touch "$HTTP_FLAG"
            log "forwarding tailnet TCP :${HTTP_PORT} to 127.0.0.1:${KASM_PORT}"
        else
            log "could not configure TCP :${HTTP_PORT}; will retry"
        fi
    fi

    if [ "$HTTPS_PORT" != "0" ] && [ ! -f "$HTTPS_FLAG" ]; then
        current="$(serve_status)"
        if printf '%s\n' "$current" | grep -q ":${HTTPS_PORT}\b"; then
            touch "$HTTPS_FLAG"
        elif tailscale serve --bg --tls-terminated-tcp="$HTTPS_PORT" "tcp://127.0.0.1:${KASM_PORT}"; then
            touch "$HTTPS_FLAG"
            log "TLS-terminating tailnet TCP :${HTTPS_PORT} to 127.0.0.1:${KASM_PORT}"
        else
            log "could not configure TLS TCP :${HTTPS_PORT}; HTTP path remains available"
        fi
    fi

    sleep "$INTERVAL"
done
