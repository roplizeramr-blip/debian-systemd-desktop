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
# Tailscale's documented userspace recipe runs a local SOCKS5 + HTTP proxy so
# container processes can reach the tailnet for *outbound* traffic:
#   tailscaled --tun=userspace-networking \
#     --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055
# Inbound "tailscale serve" does not need it, but it lets the desktop reach
# other tailnet hosts and allows self-checks from inside the container.  It is
# bound to localhost only, so it is never exposed publicly.  Kernel mode uses
# /dev/net/tun instead, so the proxy is disabled there.
PROXY_ARGS=(--socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055)
if [ "$TUN_MODE" = "kernel" ]; then
    if [ -c /dev/net/tun ]; then
        TUN_ARGS=()
        PROXY_ARGS=()
    else
        echo "[tailscale] TS_TUN=kernel requested but /dev/net/tun is missing; using userspace" >&2
    fi
fi

echo "[tailscale] starting tailscaled (tun=$(if [ "${#TUN_ARGS[@]}" -eq 0 ]; then echo kernel; else echo userspace; fi), local proxy=$(if [ "${#PROXY_ARGS[@]}" -eq 0 ]; then echo off; else echo localhost:1055; fi))"
exec /usr/sbin/tailscaled \
    "${TUN_ARGS[@]}" \
    "${PROXY_ARGS[@]}" \
    --state="${STATE_DIR}/tailscaled.state"
