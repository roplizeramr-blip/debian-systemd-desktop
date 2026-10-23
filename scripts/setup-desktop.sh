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

# --- Performance: no compositor, no animations, no shadows -----------------
set_prop xfwm4 /general/use_compositing bool false
set_prop xfwm4 /general/box_move bool false
set_prop xfwm4 /general/box_resize bool false
set_prop xfwm4 /general/cycle_draw_frame bool false
set_prop xfwm4 /general/show_frame_shadow bool false
set_prop xfwm4 /general/show_popup_shadow bool false
set_prop xfwm4 /general/snap_to_border bool false
set_prop xfwm4 /general/snap_to_window bool false
set_prop xfwm4 /general/workspace_count int 1
set_prop xfwm4 /general/title_font string "Noto Sans Bold 10"
set_prop xfwm4 /general/title_alignment string "left"

# --- GTK / Xsettings: flat, dark and animation-free ------------------------
set_prop xsettings /Gtk/EnableAnimations bool false
set_prop xsettings /Net/ThemeName string "Adwaita-dark"
set_prop xsettings /Net/IconThemeName string "Adwaita"
set_prop xsettings /Gtk/FontName string "Noto Sans 10"
set_prop xsettings /Gtk/MonospaceFontName string "Noto Sans Mono 10"
set_prop xsettings /Xft/Antialias int 1
set_prop xsettings /Xft/Hinting int 1
set_prop xsettings /Xft/HintStyle string "hintslight"
set_prop xsettings /Xft/RGBA string "none"
set_prop xsettings /Net/EnableEventSounds bool false
set_prop xsettings /Net/EnableInputFeedbackSounds bool false

# --- Session, screensaver and power ---------------------------------------
set_prop xfce4-session /general/SaveOnExit bool false
set_prop xfce4-session /general/AutoSave bool false
set_prop xfce4-screensaver /saver/enabled bool false
set_prop xfce4-screensaver /lock/enabled bool false
set_prop xfce4-power-manager /xfce4-power-manager/blank-on-ac int 0
set_prop xfce4-power-manager /xfce4-power-manager/dpms-enabled bool false
set_prop xfce4-power-manager /xfce4-power-manager/inactivity-on-ac int 0

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

# No screen blanking or DPMS: a remote desktop should not go black.
if command -v xset >/dev/null 2>&1; then
    xset s off -dpms >/dev/null 2>&1 || true
fi

# Do not start services we explicitly replaced with lightweight settings.
install -d "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/xfce4-power-manager.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Power Manager
Hidden=true
EOF
cat > "$HOME/.config/autostart/xfce4-screensaver.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Screensaver
Hidden=true
EOF

# Persist the flat GTK look for GTK3 and GTK4 applications.
install -d "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
for gtk_dir in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
    cat > "$gtk_dir/settings.ini" <<'EOF'
[Settings]
gtk-enable-animations=0
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=Noto Sans 10
gtk-application-prefer-dark-theme=1
EOF
done

# A light terminal with a sensible scrollback and no cursor blink.
install -d "$HOME/.config/xfce4/terminal"
cat > "$HOME/.config/xfce4/terminal/terminalrc" <<'EOF'
[Configuration]
FontName=Noto Sans Mono 10
MiscAlwaysShowTabs=FALSE
MiscShowUnsafePasteDialog=FALSE
MiscCursorBlinks=FALSE
ScrollingLines=2000
EOF

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
