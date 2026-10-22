#!/bin/bash
set -Eeuo pipefail

export VNC_PW="${VNC_PW:-Ubuntu26}"
# Legacy VNC authentication uses at most 8 characters.  Truncate instead of
# letting vncpasswd fail when a longer value is supplied.
if [ "${#VNC_PW}" -gt 8 ]; then
    VNC_PW="${VNC_PW:0:8}"
fi
export VNC_RESOLUTION="${VNC_RESOLUTION:-1440x900}"
export VNC_PORT="${VNC_PORT:-5901}"
export NOVNC_PORT="${NOVNC_PORT:-${PORT:-3000}}"
export TZ="${TZ:-Africa/Cairo}"
export SYSTEMD_DETECT_VIRT="${SYSTEMD_DETECT_VIRT:-none}"

if ! locale -a 2>/dev/null | grep -qi '^en_US\.utf8$'; then
    export LANG="C.UTF-8"
    export LANGUAGE="C.UTF-8"
    export LC_ALL="C.UTF-8"
else
    export LANG="${LANG:-en_US.UTF-8}"
    export LANGUAGE="${LANGUAGE:-en_US:en}"
    export LC_ALL="${LC_ALL:-en_US.UTF-8}"
fi

if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
    printf '%s\n' "$TZ" > /etc/timezone
fi

# Runtime directories that systemd normally creates.  Remove sockets and X11
# lock files left behind by a previous container run before starting fresh.
rm -f /run/dbus/system_bus_socket /run/dbus/pid /run/supervisor.sock
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
install -d -m 0755 /run/systemd/system /run/systemd/journal /run/dbus
install -d -m 1777 /tmp/.X11-unix
install -d -m 0755 /var/log/supervisor /var/log/journal
install -d -m 0700 -o desktop -g desktop /run/user/1000
install -d -m 0700 -o desktop -g desktop /home/desktop/.vnc
install -d -m 0755 -o desktop -g desktop \
    /home/desktop/.config /home/desktop/.cache /home/desktop/Desktop

# A stable machine-id and boot timestamp make hostnamectl/journalctl useful.
if [ ! -s /etc/machine-id ]; then
    if command -v systemd-machine-id-setup >/dev/null 2>&1; then
        systemd-machine-id-setup 2>/dev/null || true
    fi
    if [ ! -s /etc/machine-id ]; then
        tr -d '-' < /proc/sys/kernel/random/uuid > /etc/machine-id
    fi
fi
date +%s > /run/systemd/system/boot-time

if [ -n "${DESKTOP_HOSTNAME:-}" ]; then
    hostname "$DESKTOP_HOSTNAME" 2>/dev/null || true
    printf '%s\n' "$DESKTOP_HOSTNAME" > /etc/hostname 2>/dev/null || true
fi

# VNC password.  vncpasswd stores a fixed-size obfuscated value, not the
# plaintext password.
printf '%s\n' "$VNC_PW" | vncpasswd -f > /home/desktop/.vnc/passwd
chown desktop:desktop /home/desktop/.vnc/passwd
chmod 0600 /home/desktop/.vnc/passwd

cat > /home/desktop/.vnc/xstartup <<'XSTARTUP'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec dbus-run-session -- startxfce4
XSTARTUP
chmod 0755 /home/desktop/.vnc/xstartup
chown desktop:desktop /home/desktop/.vnc/xstartup

# /dev/log is expected by syslog-style applications.  The journald shim
# creates the real socket at /run/systemd/journal/dev-log.
rm -f /dev/log 2>/dev/null || true
ln -sfn /run/systemd/journal/dev-log /dev/log 2>/dev/null || true

# Optional compatibility switch: removing /.dockerenv makes some simple
# container checks less noisy.  It is disabled by default and is not a
# security boundary.  Set HIDE_CONTAINER=1 only if you understand that.
if [ "${HIDE_CONTAINER:-0}" = "1" ]; then
    rm -f /.dockerenv
fi

exec "$@"
