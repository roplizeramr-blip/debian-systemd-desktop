#!/bin/bash
# Publish KasmVNC on the Tailscale link, not on the raw Tailscale IP:
#
#   https://<host>.<tailnet>.ts.net/  ->  http://127.0.0.1:6080  (tailnet)
#   tailnet TCP :3000                 ->  tcp://127.0.0.1:6080   (opt-in)
#
# The primary rule is an HTTPS reverse proxy created with `tailscale serve`
# (private, tailnet only) or `tailscale funnel` (public on the internet).  Both
# terminate TLS with a certificate that Tailscale provisions for the MagicDNS
# name and forward HTTP *and* WebSocket traffic to KasmVNC.  "Open VNC"
# therefore uses the MagicDNS link and no port on the Tailscale IP is consumed,
# which leaves the IP and its ports free for other apps hosted on the node.
#
# Privacy: TS_FUNNEL=0 (default) keeps the desktop reachable only from devices
# signed in to the same tailnet.  TS_FUNNEL=1 uses `tailscale funnel`, which
# makes the login page reachable by anyone on the internet at the same URL (the
# KasmVNC password is still required).  Funnel also needs the `funnel` node
# attribute and HTTPS enabled for the tailnet; `tailscale funnel` adds the node
# attribute automatically when run by a tailnet admin.
#
# Serving HTTPS on the ts.net name needs MagicDNS and HTTPS certificates to be
# enabled for the tailnet in the Tailscale admin console (DNS page).  The raw
# TCP rule is a fallback only and is disabled by default; set
# TS_SERVE_HTTP_PORT (and optionally TS_SERVE_FALLBACK_TCP=1) to opt in.
set -uo pipefail

KASM_PORT="${KASM_PORT:-6080}"
HTTPS_PORT="${TS_SERVE_HTTPS_PORT:-443}"
HTTP_PORT="${TS_SERVE_HTTP_PORT:-0}"
FALLBACK_TCP="${TS_SERVE_FALLBACK_TCP:-0}"
FUNNEL="${TS_FUNNEL:-0}"
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

# True (exit 0) when `tailscale serve status --json` already has the HTTPS rule
# we want on the given port.  When FUNNEL=1 the rule must also be marked public
# in "AllowFunnel"; a tailnet-only rule then counts as "not done yet" so the
# loop upgrades it.  The JSON keys look like "<host>.<tailnet>.ts.net:443", so
# an exact port suffix match avoids confusing 443 with 4430.
https_ok() {
    tailscale serve status --json 2>/dev/null | python3 -c '
import json, sys
port = sys.argv[1]
want_public = sys.argv[2] == "1"
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
web = data.get("Web") or {}
key = next((k for k in web if str(k).endswith(":" + port)), None)
if key is None:
    sys.exit(1)
if want_public:
    allow = data.get("AllowFunnel") or {}
    sys.exit(0 if allow.get(key) is True else 1)
sys.exit(0)
' "$HTTPS_PORT" "$FUNNEL"
}

serve_has_tcp() {
    tailscale serve status --json 2>/dev/null | python3 -c '
import json, sys
port = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
tcp = data.get("TCP") or {}
for key in tcp:
    if str(key).endswith(":" + port):
        sys.exit(0)
sys.exit(1)
' "$HTTP_PORT"
}

https_failures=0

if [ "$FUNNEL" = "1" ]; then
    log "mode: Funnel (public on the internet). The KasmVNC login page will be reachable by anyone; a password is still required."
else
    log "mode: Serve (tailnet only)"
fi

while true; do
    state="$(backend_state)"
    if [ "$state" != "Running" ]; then
        rm -f "$HTTP_FLAG" "$HTTPS_FLAG"
        https_failures=0
        sleep "$INTERVAL"
        continue
    fi

    # A flag is only trusted while the corresponding rule is still present and
    # still has the requested visibility.  This also recovers if tailscaled
    # restarts with an empty Serve config, or if it was switched to Funnel on
    # another port by hand.
    if [ -f "$HTTP_FLAG" ] && ! serve_has_tcp; then
        rm -f "$HTTP_FLAG"
    fi
    if [ -f "$HTTPS_FLAG" ] && ! https_ok; then
        rm -f "$HTTPS_FLAG"
    fi

    if [ "$HTTPS_PORT" != "0" ] && [ ! -f "$HTTPS_FLAG" ]; then
        if https_ok; then
            touch "$HTTPS_FLAG"
            https_failures=0
        elif [ "$FUNNEL" = "1" ]; then
            if tailscale funnel --bg --https="$HTTPS_PORT" "http://127.0.0.1:${KASM_PORT}"; then
                touch "$HTTPS_FLAG"
                https_failures=0
                log "publishing the public Funnel link on :${HTTPS_PORT} -> 127.0.0.1:${KASM_PORT}"
            else
                https_failures=$((https_failures + 1))
                log "could not configure Funnel :${HTTPS_PORT} (attempt ${https_failures}); is Funnel allowed for your tailnet?"
            fi
        elif tailscale serve --bg --https="$HTTPS_PORT" "http://127.0.0.1:${KASM_PORT}"; then
            touch "$HTTPS_FLAG"
            https_failures=0
            log "publishing the Tailscale HTTPS link on :${HTTPS_PORT} -> 127.0.0.1:${KASM_PORT}"
        else
            https_failures=$((https_failures + 1))
            log "could not configure HTTPS :${HTTPS_PORT} (attempt ${https_failures}); is HTTPS enabled for the tailnet in the Tailscale admin console?"
        fi
    fi

    if [ "$HTTP_PORT" != "0" ] && [ ! -f "$HTTP_FLAG" ]; then
        if serve_has_tcp; then
            touch "$HTTP_FLAG"
        elif tailscale serve --bg --tcp="$HTTP_PORT" "tcp://127.0.0.1:${KASM_PORT}"; then
            touch "$HTTP_FLAG"
            log "fallback: forwarding tailnet TCP :${HTTP_PORT} to 127.0.0.1:${KASM_PORT}"
        else
            log "could not configure TCP :${HTTP_PORT}; will retry"
        fi
    fi

    # Optional escape hatch: if HTTPS/Funnel certificates are unavailable and
    # the operator accepts using a port on the Tailscale IP, turn on the raw TCP
    # rule after a few failed attempts.
    if [ "$FALLBACK_TCP" = "1" ] && [ "$HTTPS_PORT" != "0" ] \
        && [ ! -f "$HTTPS_FLAG" ] && [ "$https_failures" -ge 3 ] \
        && [ "$HTTP_PORT" = "0" ]; then
        HTTP_PORT=3000
        log "enabling raw TCP fallback on :${HTTP_PORT} after ${https_failures} HTTPS failures"
    fi

    sleep "$INTERVAL"
done
