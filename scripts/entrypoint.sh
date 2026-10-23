#!/bin/bash
set -Eeuo pipefail

export VNC_PW="${VNC_PW:-Ubuntu26}"
# Legacy VNC authentication uses at most 8 characters.  Truncate instead of
# letting tigervncpasswd fail when a longer value is supplied.
if [ "${#VNC_PW}" -gt 8 ]; then
    VNC_PW="${VNC_PW:0:8}"
fi
export VNC_RESOLUTION="${VNC_RESOLUTION:-1440x900}"
export VNC_PORT="${VNC_PORT:-5901}"
export NOVNC_PORT="${NOVNC_PORT:-${PORT:-3000}}"
export TZ="${TZ:-Africa/Cairo}"
export SYSTEMD_DETECT_VIRT="${SYSTEMD_DETECT_VIRT:-none}"
export SWAP_ENABLED="${SWAP_ENABLED:-1}"
export SWAP_DIR="${SWAP_DIR:-/var/swap}"
export SWAP_FILE="${SWAP_FILE:-${SWAP_DIR}/swapfile}"
export SWAP_SIZE_MB="${SWAP_SIZE_MB:-6144}"
export SWAP_SPARSE="${SWAP_SPARSE:-0}"
export VNC_FRAME_RATE="${VNC_FRAME_RATE:-30}"
export VNC_COMPARE_FB="${VNC_COMPARE_FB:-2}"
export VNC_ZLIB_LEVEL="${VNC_ZLIB_LEVEL:-1}"

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

# Best-effort kernel memory tuning. /proc/sys is read-only in some containers;
# a failure here must never stop the desktop from starting.
for setting in \
    "vm.swappiness=10" \
    "vm.vfs_cache_pressure=50" \
    "vm.dirty_background_ratio=5" \
    "vm.dirty_ratio=10" \
    "fs.inotify.max_user_watches=524288"; do
    sysctl -w "$setting" >/dev/null 2>&1 || true
done

echo "[desktop] VNC ${VNC_RESOLUTION} on ${VNC_PORT}; frame rate ${VNC_FRAME_RATE}; zlib ${VNC_ZLIB_LEVEL}"
echo "[desktop] swap ${SWAP_SIZE_MB} MiB at ${SWAP_FILE} (sparse=${SWAP_SPARSE}, enabled=${SWAP_ENABLED})"

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

# VNC password.  tigervncpasswd stores a fixed-size obfuscated value, not the
# plaintext password.
printf '%s\n' "$VNC_PW" | tigervncpasswd -f > /home/desktop/.vnc/passwd
chown desktop:desktop /home/desktop/.vnc/passwd
chmod 0600 /home/desktop/.vnc/passwd

# Linux login/sudo password. Supply DESKTOP_PW from the deployment's private
# environment so the public image and repository never bake a secret. If it is
# absent, the account stays locked and only the VNC password is usable.
if [ -n "${DESKTOP_PW:-}" ]; then
    if printf 'desktop:%s\n' "$DESKTOP_PW" | chpasswd 2>/dev/null; then
        usermod -U desktop 2>/dev/null || true
        echo "[desktop] Linux password updated from DESKTOP_PW"
    else
        echo "[desktop] WARNING: could not set Linux password from DESKTOP_PW"
    fi
else
    echo "[desktop] DESKTOP_PW is not set; Linux account desktop remains locked"
fi

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

# Create the swap file in a writable folder and try to activate it.  This is
# asynchronous on purpose: a 6 GiB file must never delay VNC/noVNC startup.
# On CranL the file is created but swapon is blocked by the container runtime;
# setup-swap.sh records the exact result in the noVNC status JSON.
if [ "${SWAP_ENABLED:-1}" = "1" ]; then
    /usr/local/bin/setup-swap.sh >/var/log/swap.log 2>&1 &
fi

# Optional compatibility switch: removing /.dockerenv makes some simple
# container checks less noisy.  It is disabled by default and is not a
# security boundary.  Set HIDE_CONTAINER=1 only if you understand that.
if [ "${HIDE_CONTAINER:-0}" = "1" ]; then
    rm -f /.dockerenv
fi

exec "$@"
