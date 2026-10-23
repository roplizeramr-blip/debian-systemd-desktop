#!/bin/bash
set -Eeuo pipefail

export HOME="${HOME:-/home/desktop}"
export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export XDG_SESSION_TYPE="x11"
export XDG_CURRENT_DESKTOP="XFCE"
export XDG_SESSION_DESKTOP="xfce"
export GDK_BACKEND="x11"
export NO_AT_BRIDGE="1"
export MOZ_ENABLE_WAYLAND="0"
# Firefox's content sandbox can fail under restrictive container seccomp
# profiles.  The parent sandbox remains enabled; set this to 0 to re-enable
# the content sandbox if your runtime supports user namespaces.
export MOZ_DISABLE_CONTENT_SANDBOX="${MOZ_DISABLE_CONTENT_SANDBOX:-1}"

mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Supervisor starts this unit shortly after KasmVNC; allow Xvnc a few seconds
# to create the display socket instead of burning restart attempts.
for _ in $(seq 1 150); do
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

# Run setup-desktop inside the same session bus as XFCE.  xfconf-query talks
# to xfconfd over DBUS_SESSION_BUS_ADDRESS, so a separate Supervisor program
# would not see the running session.
exec dbus-run-session -- bash -c '
    startxfce4 &
    xfce_pid=$!
    (sleep 2; /usr/local/bin/setup-desktop.sh) &
    wait "$xfce_pid"
'
