# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG KASM_VERSION=1.5.0
ARG KASM_SHA256=f599fe02e2175b9817b6165f74a5d2bebdc73118dde9181ba3410963bed7ae1e

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    TZ=Africa/Cairo \
    DISPLAY=:1 \
    KASM_PORT=6080 \
    KASM_DISPLAY=1 \
    CONTROL_PORT=3000 \
    VNC_RESOLUTION=1440x900 \
    VNC_USER=desktop \
    VNC_AUTH=1 \
    VNC_FRAME_RATE=60 \
    SWAP_ENABLED=0 \
    SWAP_DIR=/var/swap \
    SWAP_FILE=/var/swap/swapfile \
    SWAP_SIZE_MB=6144 \
    SWAP_SPARSE=1 \
    SYSTEMD_DETECT_VIRT=none \
    HIDE_CONTAINER=0 \
    FIREFOX_NO_SANDBOX=0 \
    DESKTOP_HOSTNAME=ubuntu-desktop \
    TS_HOSTNAME=ubuntu-desktop \
    TS_STATE_DIR=/var/lib/tailscale \
    TS_TUN=userspace \
    TS_SERVE_HTTPS_PORT=443 \
    TS_SERVE_HTTP_PORT=0 \
    TS_SERVE_FALLBACK_TCP=0 \
    TS_FUNNEL=0 \
    TS_SERVE_INTERVAL=10 \
    DEBIAN_FRONTEND=noninteractive

# Keep the base current.  The desktop is intentionally lean: KasmVNC replaces
# TigerVNC + noVNC + websockify, and Tailscale supplies private access without
# publishing a VNC port.  ssl-cert is required by KasmVNC's bundled web server.
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
        locales tzdata sudo passwd procps psmisc iproute2 net-tools hostname less nano \
        dbus dbus-x11 \
        python3 python3-dbus python3-gi gir1.2-glib-2.0 \
        supervisor systemd \
        earlyoom kmod ssl-cert \
        xfce4 xfce4-terminal xfce4-screenshooter xfce4-taskmanager xfce4-appfinder \
        thunar mousepad ristretto \
        x11-utils x11-xserver-utils x11-xkb-utils xauth xdg-utils desktop-file-utils \
        xfonts-base xfonts-utils adwaita-icon-theme \
        fonts-dejavu-core fonts-noto-core fonts-noto-color-emoji fonts-liberation \
        librsvg2-common \
    && rm -rf /var/lib/apt/lists/*

# Firefox from Mozilla's official APT repository.  Ubuntu's firefox package is
# a snap transitional package and does not work inside a normal container.
# Mozilla's APT repository ships the browser only, so fetch the matching Arabic
# language pack from Mozilla's official release directory and install it as a
# system-wide browser extension.
RUN install -d -m 0755 /etc/apt/keyrings \
    && wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg \
        -O /etc/apt/keyrings/packages.mozilla.org.asc \
    && echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
        > /etc/apt/sources.list.d/mozilla.list \
    && printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
        > /etc/apt/preferences.d/mozilla \
    && apt-get update \
    && apt-get install -y --no-install-recommends firefox \
    && FIREFOX_VERSION="$(dpkg-query -W -f='${Version}' firefox | sed 's/[~+].*//')" \
    && test -n "$FIREFOX_VERSION" \
    && install -d -m 0755 /usr/lib/firefox/browser/extensions \
    && wget -q "https://ftp.mozilla.org/pub/firefox/releases/${FIREFOX_VERSION}/linux-x86_64/xpi/ar.xpi" \
        -O /usr/lib/firefox/browser/extensions/langpack-ar@firefox.mozilla.org.xpi \
    && chmod 0644 /usr/lib/firefox/browser/extensions/langpack-ar@firefox.mozilla.org.xpi \
    && rm -rf /var/lib/apt/lists/*

# Tailscale (userspace networking mode by default; no TUN/NET_ADMIN needed).
RUN install -d -m 0755 /usr/share/keyrings \
    && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
        -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
    && chmod 0644 /usr/share/keyrings/tailscale-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu noble main" \
        > /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends tailscale \
    && rm -rf /var/lib/apt/lists/*

# KasmVNC 1.5.0: a single HTTP/WebSocket server with adaptive encoding, no
# Java/Flash and no separate websockify process.  The checksum is pinned so a
# changed GitHub asset cannot silently enter the image.
RUN curl -fsSL \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASM_VERSION}/kasmvncserver_noble_${KASM_VERSION}_amd64.deb" \
        -o /tmp/kasmvnc.deb \
    && echo "${KASM_SHA256}  /tmp/kasmvnc.deb" | sha256sum -c - \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/kasmvnc.deb \
    && rm -f /tmp/kasmvnc.deb \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen

# Do not bake a Linux password into the public image. The entrypoint applies
# DESKTOP_PW from the deployment's private environment at container start.
# The desktop user is in ssl-cert so KasmVNC can read the snakeoil key.
RUN set -eux; \
    if getent passwd desktop >/dev/null; then userdel -r desktop 2>/dev/null || true; fi; \
    for existing_user in $(getent passwd 1000 | cut -d: -f1); do userdel -r "$existing_user" 2>/dev/null || true; done; \
    for existing_group in $(getent group 1000 | cut -d: -f1); do groupdel "$existing_group" 2>/dev/null || true; done; \
    if ! getent group desktop >/dev/null; then \
        groupadd -g 1000 desktop 2>/dev/null || groupadd desktop; \
    fi; \
    useradd -m -u 1000 -g desktop -s /bin/bash -G sudo,ssl-cert desktop; \
    passwd -l root; \
    install -d -m 0755 -o desktop -g desktop /home/desktop/Desktop; \
    install -d -m 0755 -o desktop -g desktop /home/desktop/.config; \
    install -d -m 0755 -o desktop -g desktop /home/desktop/.cache; \
    install -d -m 0700 -o desktop -g desktop /home/desktop/.vnc

# Compatibility layer, units, D-Bus facade and desktop assets.
RUN install -d -m 0755 /opt/systemd-compat /usr/share/backgrounds /etc/firefox \
        /usr/share/applications /home/desktop/.mozilla/firefox/desktop.default-release \
        /etc/supervisor/conf.d
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY systemd/units/ /etc/systemd/system/
COPY systemd/systemd_compat.py /opt/systemd-compat/systemd_compat.py
COPY systemd/systemd_dbus.py /opt/systemd-compat/systemd_dbus.py
COPY systemd/systemd-journald.py /opt/systemd-compat/systemd-journald.py
COPY systemd/systemctl.py /opt/systemd-compat/systemctl.py
COPY systemd/systemd-detect-virt.py /opt/systemd-compat/systemd-detect-virt.py
COPY systemd/hostnamectl.py /opt/systemd-compat/hostnamectl.py
COPY systemd/timedatectl.py /opt/systemd-compat/timedatectl.py
COPY systemd/loginctl.py /opt/systemd-compat/loginctl.py
COPY systemd/journalctl.py /opt/systemd-compat/journalctl.py
COPY systemd/systemd-analyze.py /opt/systemd-compat/systemd-analyze.py
COPY systemd/dbus/org.freedesktop.systemd1.service /usr/share/dbus-1/system-services/org.freedesktop.systemd1.service
COPY systemd/dbus/org.freedesktop.systemd1.conf /etc/dbus-1/system.d/org.freedesktop.systemd1.conf
COPY scripts/ /usr/local/bin/
COPY desktop/wallpaper.svg /usr/share/backgrounds/ubuntu-cloud.svg
COPY desktop/firefox-syspref.js /etc/firefox/syspref.js
COPY desktop/firefox-policies.json /usr/lib/firefox/distribution/policies.json
COPY desktop/firefox-user.js /home/desktop/.mozilla/firefox/desktop.default-release/user.js
COPY desktop/profiles.ini /home/desktop/.mozilla/firefox/profiles.ini
# Keep custom launchers out of /usr/share/applications so they do not replace
# the package-provided Firefox/Thunar/Settings entries.  The package entries
# stay in the application menu; the Arabic launchers are used on the desktop.
COPY desktop/applications/ /opt/desktop/applications/
COPY web/ /opt/desktop/web/
COPY web/welcome.html /opt/desktop/welcome.html
COPY tests/ /opt/desktop/tests/

# Replace the real systemd CLI tools with the Supervisor-backed facade.  The
# real binaries are kept as *.real for debugging, but they cannot work without
# systemd as PID 1.
RUN ln -sfn /usr/bin/supervisord /usr/local/bin/systemd \
    && ln -sfn /usr/local/bin/firefox-wrapper.sh /usr/local/bin/firefox \
    && ln -sfn /opt/systemd-compat/systemctl.py /usr/local/bin/systemctl \
    && ln -sfn /opt/systemd-compat/systemd-detect-virt.py /usr/local/bin/systemd-detect-virt \
    && ln -sfn /opt/systemd-compat/hostnamectl.py /usr/local/bin/hostnamectl \
    && ln -sfn /opt/systemd-compat/timedatectl.py /usr/local/bin/timedatectl \
    && ln -sfn /opt/systemd-compat/loginctl.py /usr/local/bin/loginctl \
    && ln -sfn /opt/systemd-compat/journalctl.py /usr/local/bin/journalctl \
    && ln -sfn /opt/systemd-compat/systemd-analyze.py /usr/local/bin/systemd-analyze \
    && for cmd in systemctl systemd-detect-virt hostnamectl timedatectl loginctl journalctl systemd-analyze; do \
        if [ -e "/usr/bin/$cmd" ] && [ ! -L "/usr/bin/$cmd" ]; then \
            mv "/usr/bin/$cmd" "/usr/bin/$cmd.real"; \
        fi; \
        ln -sfn "/usr/local/bin/$cmd" "/usr/bin/$cmd"; \
    done \
    && chmod 0755 /usr/local/bin/*.sh /usr/local/bin/control-server.py /opt/systemd-compat/*.py

# Enable the core units in the same way systemctl enable would.
RUN mkdir -p /etc/systemd/system/graphical.target.wants \
             /etc/systemd/system/multi-user.target.wants \
    && ln -sfn /etc/systemd/system/kasmvnc.service /etc/systemd/system/graphical.target.wants/kasmvnc.service \
    && ln -sfn /etc/systemd/system/xfce.service /etc/systemd/system/graphical.target.wants/xfce.service \
    && ln -sfn /etc/systemd/system/control.service /etc/systemd/system/graphical.target.wants/control.service \
    && ln -sfn /etc/systemd/system/tailscaled.service /etc/systemd/system/graphical.target.wants/tailscaled.service \
    && ln -sfn /etc/systemd/system/tailscale-serve.service /etc/systemd/system/graphical.target.wants/tailscale-serve.service \
    && ln -sfn /etc/systemd/system/dbus.service /etc/systemd/system/multi-user.target.wants/dbus.service \
    && ln -sfn /etc/systemd/system/systemd-journald.service /etc/systemd/system/multi-user.target.wants/systemd-journald.service \
    && ln -sfn /etc/systemd/system/systemd-dbus.service /etc/systemd/system/multi-user.target.wants/systemd-dbus.service \
    && ln -sfn /etc/systemd/system/graphical.target /etc/systemd/system/default.target

# Desktop launchers, Firefox profile ownership and runtime log directories.
RUN cp /opt/desktop/applications/*.desktop /home/desktop/Desktop/ \
    && chmod 0755 /home/desktop/Desktop/*.desktop \
    && mkdir -p /home/desktop/.mozilla/firefox/desktop.default-release /etc/supervisor/conf.d \
    && install -d -m 0755 -o desktop -g desktop /home/desktop/.mozilla/firefox/desktop.default-release/extensions \
    && cp /usr/lib/firefox/browser/extensions/langpack-ar@firefox.mozilla.org.xpi /home/desktop/.mozilla/firefox/desktop.default-release/extensions/ \
    && chown -R desktop:desktop /home/desktop /opt/desktop \
    && install -d -m 0755 /var/log/supervisor /var/log/journal \
    && install -d -m 0700 /var/swap \
    && install -d -m 0700 /var/lib/tailscale \
    && install -d -m 0755 /var/run/tailscale \
    && install -d -m 0755 /opt/systemd-compat
RUN update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
RUN fc-cache -f >/dev/null 2>&1 || true

# Make the compatibility tools executable even if the COPY preserved modes.
RUN chmod 0755 /opt/systemd-compat/*.py /usr/local/bin/*.sh /usr/local/bin/control-server.py /opt/desktop/tests/*.sh

HEALTHCHECK --interval=30s --timeout=8s --start-period=90s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

EXPOSE 3000
WORKDIR /home/desktop
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/systemd", "-n", "-c", "/etc/supervisor/supervisord.conf"]
