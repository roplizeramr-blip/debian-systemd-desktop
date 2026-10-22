#!/bin/bash
set -Eeuo pipefail

export HOME="${HOME:-/home/desktop}"
export DISPLAY="${DISPLAY:-:1}"
export VNC_PORT="${VNC_PORT:-5901}"
export VNC_RESOLUTION="${VNC_RESOLUTION:-1440x900}"

mkdir -p "$HOME/.vnc"
if [ ! -s "$HOME/.vnc/passwd" ]; then
    printf '%s\n' "${VNC_PW:-Ubuntu26}" | tigervncpasswd -f > "$HOME/.vnc/passwd"
    chmod 0600 "$HOME/.vnc/passwd"
fi

args=(
    ":1"
    -geometry "$VNC_RESOLUTION"
    -depth 24
    -dpi 96
    -rfbauth "$HOME/.vnc/passwd"
    -rfbport "$VNC_PORT"
    -AlwaysShared
    -AcceptKeyEvents
    -AcceptPointerEvents
    -AcceptCutText
    -SendCutText
    -SecurityTypes VncAuth
)

# Keep VNC on loopback; websockify is the only public listener.
if [ "${VNC_BIND_ALL:-0}" != "1" ]; then
    args+=(-localhost)
fi

exec Xvnc "${args[@]}"
