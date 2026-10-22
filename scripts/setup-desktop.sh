#!/bin/bash
set -Eeuo pipefail

export HOME="${HOME:-/home/desktop}"
export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
WALLPAPER="/usr/share/backgrounds/ubuntu-cloud.svg"

set_prop() {
    local channel="$1" prop="$2" type="$3" value="$4"
    if xfconf-query -c "$channel" -p "$prop" >/dev/null 2>&1; then
        xfconf-query -c "$channel" -p "$prop" -s "$value" >/dev/null 2>&1 || true
    else
        xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value" >/dev/null 2>&1 || true
    fi
}

# Wait for xfdesktop/xfconf to become available.
for _ in $(seq 1 90); do
    if xfconf-query -c xfce4-desktop -l >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Apply the wallpaper to every monitor/workspace XFCE created.
for _ in $(seq 1 30); do
    props="$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$' || true)"
    if [ -n "$props" ]; then
        break
    fi
    sleep 1
done

if [ -n "${props:-}" ]; then
    while IFS= read -r prop; do
        [ -n "$prop" ] || continue
        xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" >/dev/null 2>&1 || true
        style="${prop%/last-image}/image-style"
        set_prop xfce4-desktop "$style" int 5
    done <<< "$props"
else
    set_prop xfce4-desktop /backdrop/screen0/monitor0/workspace0/last-image string "$WALLPAPER"
    set_prop xfce4-desktop /backdrop/screen0/monitor0/workspace0/image-style int 5
fi

# A lightweight, quiet desktop: no compositor, no screen blanking.
set_prop xfwm4 /general/use_compositing bool false
set_prop xfwm4 /general/workspace_count int 1
set_prop xfce4-power-manager /xfce4-power-manager/blank-on-ac int 0
set_prop xfce4-power-manager /xfce4-power-manager/dpms-enabled bool false
set_prop xfce4-power-manager /xfce4-power-manager/inactivity-on-ac int 0
set_prop xfce4-session /general/SaveOnExit bool false

# Desktop icons.
set_prop xfce4-desktop /desktop-icons/file-icons/show-home bool true
set_prop xfce4-desktop /desktop-icons/file-icons/show-filesystem bool true
set_prop xfce4-desktop /desktop-icons/file-icons/show-removable bool false
set_prop xfce4-desktop /desktop-icons/file-icons/show-trash bool true
set_prop xfce4-desktop /desktop-icons/file-icons/show-unknown bool true

# Arabic + US keyboard, toggled with Alt+Shift.
if command -v setxkbmap >/dev/null 2>&1; then
    setxkbmap -layout us,ara -option grp:alt_shift_toggle >/dev/null 2>&1 || true
fi

# Firefox is the default browser.
if command -v xdg-settings >/dev/null 2>&1; then
    xdg-settings set default-web-browser firefox.desktop >/dev/null 2>&1 || true
fi
if command -v xdg-mime >/dev/null 2>&1; then
    for mime in x-scheme-handler/http x-scheme-handler/https text/html; do
        xdg-mime default firefox.desktop "$mime" >/dev/null 2>&1 || true
    done
fi

if command -v xfdesktop >/dev/null 2>&1; then
    xfdesktop --reload >/dev/null 2>&1 || true
fi

echo "Desktop configuration applied for ${USER:-desktop}."
