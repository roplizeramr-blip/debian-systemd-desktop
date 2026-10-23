#!/bin/bash
set -Eeuo pipefail

export HOME="${HOME:-/home/desktop}"
export DISPLAY="${DISPLAY:-:1}"
export VNC_PORT="${VNC_PORT:-5901}"
export VNC_RESOLUTION="${VNC_RESOLUTION:-1440x900}"
export VNC_FRAME_RATE="${VNC_FRAME_RATE:-30}"
export VNC_COMPARE_FB="${VNC_COMPARE_FB:-2}"
export VNC_ZLIB_LEVEL="${VNC_ZLIB_LEVEL:-1}"
export VNC_DESKTOP_NAME="${VNC_DESKTOP_NAME:-Ubuntu Cloud Desktop}"

mkdir -p "$HOME/.vnc"
if [ ! -s "$HOME/.vnc/passwd" ]; then
    printf '%s\n' "${VNC_PW:-Ubuntu26}" | tigervncpasswd -f > "$HOME/.vnc/passwd"
    chmod 0600 "$HOME/.vnc/passwd"
fi

# Low-latency Tight encoding profile for the Xvnc server (TigerVNC 1.13):
#   FrameRate 30        cap redundant updates, smooth for noVNC
#   CompareFB 2         skip unchanged framebuffer regions
#   ZlibLevel 1         fastest server-side compression
#   ImprovedHextile     efficient text/desktop updates
#   UseBlacklist        avoid slow encodings for struggling clients
# JPEG quality and compression are negotiated by noVNC in web/index.html;
# Xvnc 1.13 does not accept -Quality or -CompressLevel, so they are omitted.
args=(
    ":1"
    -geometry "$VNC_RESOLUTION"
    -depth 24
    -dpi 96
    -rfbauth "$HOME/.vnc/passwd"
    -rfbport "$VNC_PORT"
    -desktop "$VNC_DESKTOP_NAME"
    -AlwaysShared
    -AcceptKeyEvents
    -AcceptPointerEvents
    -AcceptCutText
    -SendCutText
    -MaxCutText 1048576
    -SecurityTypes VncAuth
    -FrameRate "$VNC_FRAME_RATE"
    -CompareFB "$VNC_COMPARE_FB"
    -ZlibLevel "$VNC_ZLIB_LEVEL"
    -ImprovedHextile
    -UseBlacklist
)

# Xvnc is an X server; -noreset keeps XFCE alive when the last viewer closes.
# Probe the help output so an older build without the option still starts.
if Xvnc -help 2>&1 | grep -q -- '-noreset'; then
    args+=(-noreset)
else
    echo "Xvnc does not advertise -noreset; relying on the server default." >&2
fi

# Keep VNC on loopback; websockify is the only public listener.
if [ "${VNC_BIND_ALL:-0}" != "1" ]; then
    args+=(-localhost)
fi

echo "Starting Xvnc: ${VNC_RESOLUTION}, port ${VNC_PORT}, frame rate ${VNC_FRAME_RATE}, zlib ${VNC_ZLIB_LEVEL}."
exec Xvnc "${args[@]}"
