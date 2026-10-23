#!/bin/bash
# Optional non-interactive Tailscale onboarding.  If TS_AUTHKEY is present,
# join the tailnet automatically at boot.  Without it the public control page
# starts `tailscale up` and opens the normal login link in a new tab.
set -Eeuo pipefail

if [ -z "${TS_AUTHKEY:-}" ]; then
    echo "[tailscale] TS_AUTHKEY is not set; waiting for the control page login"
    exit 0
fi

for _ in $(seq 1 30); do
    if tailscale status >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

echo "[tailscale] joining tailnet with TS_AUTHKEY"
timeout 90s tailscale up \
    --auth-key="${TS_AUTHKEY}" \
    --hostname="${TS_HOSTNAME:-ubuntu-desktop}" \
    --accept-dns=false \
    --ssh=false || {
        echo "[tailscale] automatic join did not complete; the control page can retry"
    }
