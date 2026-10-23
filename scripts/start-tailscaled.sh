#!/bin/bash
# Keep tailscaled alive inside the container.  Tailscale userspace networking
# is the safe default: it needs no /dev/net/tun and no NET_ADMIN capability,
# and Serve still accepts inbound tailnet connections and forwards them to the
# loopback KasmVNC listener.  Set TS_TUN=kernel only on a host that grants a
# usable TUN device and NET_ADMIN.
set -Eeuo pipefail

STATE_DIR="${TS_STATE_DIR:-/var/lib/tailscale}"
RUNTIME_DIR="/var/run/tailscale"
TUN_MODE="${TS_TUN:-userspace}"

mkdir -p "$STATE_DIR" "$RUNTIME_DIR"
chmod 0700 "$STATE_DIR" 2>/dev/null || true

TUN_ARGS=(--tun=userspace-networking)
if [ "$TUN_MODE" = "kernel" ]; then
    if [ -c /dev/net/tun ]; then
        TUN_ARGS=()
    else
        echo "[tailscale] TS_TUN=kernel requested but /dev/net/tun is missing; using userspace" >&2
    fi
fi

echo "[tailscale] starting tailscaled (tun=$(if [ "${#TUN_ARGS[@]}" -eq 0 ]; then echo kernel; else echo userspace; fi))"
exec /usr/sbin/tailscaled \
    "${TUN_ARGS[@]}" \
    --state="${STATE_DIR}/tailscaled.state"
