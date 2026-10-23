# Ubuntu Cloud Desktop — systemd-compatible, Supervisor-powered

A lightweight, browser-accessible Ubuntu 24.04 XFCE desktop with Firefox,
TigerVNC, noVNC and a **systemd compatibility layer** backed by Supervisor.

The goal is practical compatibility: applications that check the usual systemd
interfaces (`systemctl`, `/run/systemd/system`, `systemd-detect-virt`,
`hostnamectl`, journald sockets, the `org.freedesktop.systemd1` D-Bus service)
see a coherent Linux system, while Supervisor remains the real process manager.

> **Honest scope:** this is a compatibility facade, not the real systemd PID 1.
> It is not a security boundary and will not fool software that deliberately
> inspects `/proc/1/exe`, cgroups, container runtimes or kernel namespaces.
> See [Known limitations](#known-limitations).

---

## Features

- Ubuntu 24.04 LTS, XFCE, TigerVNC + noVNC (browser only, no client install).
- Low-latency VNC profile: 30 fps cap, fast Tight/zlib compression, framebuffer
  comparison, improved hextile, `-noreset` session persistence, and an optimized
  noVNC URL (`quality=6`, `compression=2`, remote resize, auto-reconnect).
- A 6 GiB swap file at `/var/swap/swapfile` (writable, non-standard path), with
  an honest status page when the container runtime blocks `swapon`.
- `earlyoom` userspace OOM protection and best-effort kernel memory tuning for
  the 2 GiB desktop.
- Firefox from Mozilla's official APT repository, with Arabic localization and
  memory/network prefs tuned for a 2 GiB VNC session.
- Supervisor as PID 1; the container command is `/usr/local/bin/systemd`
  (a symlink to Supervisord) so `/proc/1/comm` reads `systemd`.
- `systemctl` shim with start/stop/restart/status/enable/disable, unit files,
  dynamic unit support and realistic status output.
- `systemd-detect-virt`, `hostnamectl`, `timedatectl`, `loginctl`,
  `journalctl`, `systemd-analyze` shims.
- A journald socket sink at `/run/systemd/journal/*` and `/dev/log`.
- A D-Bus facade for `org.freedesktop.systemd1` with Manager, Unit, Service,
  Target and Job objects.
- Custom noVNC landing page, internal welcome page and a `/healthz` endpoint.
- GitHub Actions workflow that builds and publishes to GHCR.
- Docker Compose file for local testing.

## Architecture

```
Browser ──HTTPS──► CranL edge ──► websockify/noVNC :3000
                                        │
                                        ▼ 127.0.0.1:5901
                                   TigerVNC/Xvnc
                                        │
                                        ▼ DISPLAY :1
                              XFCE + Firefox + apps
                                        │
                    ┌───────────────────┴───────────────────┐
                    │ Supervisor (PID 1, named "systemd")   │
                    │  dbus · journald · systemd-dbus       │
                    │  xvnc · xfce · novnc                  │
                    └───────────────────┬───────────────────┘
                                        │
                    systemctl shim ◄────┴────► org.freedesktop.systemd1
```

## Quick start (Docker)

```bash
docker compose up --build -d
# open http://localhost:3000
```

Or with plain Docker:

```bash
docker build -t ubuntu-systemd-desktop .
docker run -d --name ubuntu-systemd-desktop \
  -p 3000:3000 \
  --shm-size=1g \
  -e VNC_PW='Ch4ngeM3' \
  -e VNC_RESOLUTION='1440x900' \
  -e TZ='Africa/Cairo' \
  ubuntu-systemd-desktop
```

Then open `http://localhost:3000`, click **Open Desktop**, and enter the VNC
password. The default VNC password in the image is `Ubuntu26`; always override
it for a public deployment. TigerVNC VNC passwords are limited to **8
characters** (older VNC authentication); use the strongest 8-character value you
can. The default Linux password is `D3sk!2026`; change it after first login.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `NOVNC_PORT` | `3000` (or `PORT`) | Public HTTP/WebSocket port. Must match the CranL app port. |
| `VNC_PORT` | `5901` | Internal TigerVNC port, bound to loopback. |
| `VNC_RESOLUTION` | `1440x900` | Desktop geometry. |
| `VNC_PW` | `Ubuntu26` | VNC password, **maximum 8 characters**. **Change for public use.** |
| `VNC_FRAME_RATE` | `30` | Maximum updates per second per viewer. 30 is smooth and light; 60 is more responsive but uses more CPU/bandwidth. |
| `VNC_COMPARE_FB` | `2` | TigerVNC framebuffer comparison mode: `0` off, `1` always, `2` auto. |
| `VNC_ZLIB_LEVEL` | `1` | zlib compression level. `1` is the fastest; `9` is smallest. |
| `SWAP_ENABLED` | `1` | Create `/var/swap/swapfile` and try to activate it. |
| `SWAP_SIZE_MB` | `6144` | Swap file size in MiB (6 GiB). |
| `SWAP_DIR` | `/var/swap` | Writable swap directory. |
| `SWAP_FILE` | `/var/swap/swapfile` | Swap file path. |
| `SWAP_SPARSE` | `1` (image) / `0` (Compose) | `1` creates a sparse file (safe for small container disks). Use `0` on a VPS so the swap file is fully allocated. |
| `TZ` | `Africa/Cairo` | Container timezone. |
| `LANG` / `LC_ALL` | `en_US.UTF-8` | Locale; falls back to `C.UTF-8`. |
| `SYSTEMD_DETECT_VIRT` | `none` | Value returned by `systemd-detect-virt`. |
| `SYSTEMD_DETECT_VIRT_CONTAINER` | `none` | Value for `systemd-detect-virt --container`. |
| `HIDE_CONTAINER` | `0` | If `1`, removes `/.dockerenv`. Optional; not a security boundary. |
| `DESKTOP_HOSTNAME` | `ubuntu-desktop` | Hostname written to `/etc/hostname` and applied when permitted. |
| `VNC_BIND_ALL` | `0` | If `1`, Xvnc listens on all interfaces instead of loopback. |

## Performance profile

The desktop is tuned for a latency-bound browser session, not for a LAN with a
native VNC client:

- **Xvnc:** 30 fps cap, `CompareFB=2`, `ZlibLevel=1`, improved hextile and
  `-noreset` so a browser reconnect returns to the same XFCE session instead
  of restarting it.
- **noVNC:** `quality=6`, `compression=2` (Tight/JPEG settings are viewer-side;
  TigerVNC 1.13's server does not accept `-Quality` or `-CompressLevel`),
  remote resize, auto-reconnect and a
  short reconnect delay.
- **XFCE:** compositor, shadows, window animations, smooth scrolling, blanking
  and DPMS are disabled; the GTK theme is flat and dark.
- **Firefox:** software rendering, two content processes, bounded caches,
  fewer speculative network connections, no telemetry/studies.
- **Memory:** `earlyoom` protects Xvnc/XFCE from a runaway browser process; VM
  sysctls are applied best-effort.
- **Swap:** a 6 GiB file at `/var/swap/swapfile`; see below for the container
  runtime limitation.

If your link is slow, lower `VNC_RESOLUTION` (for example `1280x800`) before
lowering quality. If your link is fast and you want more responsiveness, raise
`VNC_FRAME_RATE` to `60`.

## Swap

The image creates a **6 GiB swap file at `/var/swap/swapfile`**, not at
`/swapfile`. The path is deliberately a writable folder, and the script never
blocks boot if the operation fails:

1. `setup-swap.sh` creates a sparse or fully allocated file (`SWAP_SPARSE`).
2. It runs `mkswap` and tries `swapon`.
3. If disk swap is blocked, it tries a compressed `zram` device.
4. The result is written to `/usr/share/novnc/swap-status.json` (shown on the
   landing page) and logged to `/var/log/swap.log`.

**Important:** CranL app containers do not grant `CAP_SYS_ADMIN`, so `swapon`
returns `EPERM`. Changing the path to `/var/swap` does not change that; the
kernel blocks the operation itself, not the folder. The file is ready, but it
cannot become active swap inside a CranL app. A VPS or any host that permits
swap can activate the same file. On a VPS, run `sudo scripts/host-swap.sh` on
the **host** and set `SWAP_ENABLED=0` in the container so it does not create a
second file. See [docs/DEPLOY-VPS.md](docs/DEPLOY-VPS.md).

## Credentials

| Item | Default |
|---|---|
| VNC password | `Ubuntu26` (`VNC_PW`) |
| Linux user | `desktop` |
| Linux password | `D3sk!2026` |
| sudo | user is in the `sudo` group; password required |

Change the Linux password inside the desktop:

```bash
passwd
```

- VNC password must be **8 characters or fewer**; longer values are truncated by the legacy VNC authentication scheme.
- Changing `VNC_PW` requires a container restart. The Linux password is baked
into the image at build time; change it after first login.

## systemd compatibility matrix

| Interface | Status | Notes |
|---|---|---|
| `/run/systemd/system` | ✅ | Created at startup; `sd_booted()` returns true. |
| `systemctl start/stop/restart/status` | ✅ | Backed by Supervisor. |
| `systemctl enable/disable` | ✅ | Unit symlinks + dynamic Supervisor autostart. Core services are static Supervisor programs, so disabling one does not remove it from the image's boot config. |
| `systemctl is-active/is-enabled/is-system-running` | ✅ | Realistic output and exit codes. |
| `systemctl list-units/list-unit-files/show/cat` | ✅ | Reads standard unit directories. |
| Dynamic unit files | ✅ | Generates a Supervisor program on demand. |
| `systemd-detect-virt` | ✅ | Defaults to `none`; configurable. |
| `hostnamectl` / `timedatectl` / `loginctl` | ✅ | Practical subset. |
| `journalctl` | ✅ | Reads the journald sink and Supervisor logs. |
| `/run/systemd/journal/socket`, `/dev/log` | ✅ | Datagram sink writes to `/var/log/journal/compat.log`. |
| D-Bus `org.freedesktop.systemd1` | ✅ | Manager/Unit/Service/Target/Job subset. |
| `/proc/1/comm` | ✅ | PID 1 is a Supervisord process named `systemd`. |
| Real systemd cgroup hierarchy | ❌ | Supervisor cgroups only. |
| `systemd-analyze` full feature set | ⚠️ | `time`, `blame`, `verify`, `cat-config`. |
| `systemctl reboot/poweroff` | ❌ | Refused inside the container. |
| Snap packages | ❌ | Snapd does not work in this image. |
| Kernel/namespace spoofing | ❌ | Not attempted. |

## How the Supervisor mapping works

Core units have static Supervisor programs with matching names:

| Unit | Supervisor program |
|---|---|
| `dbus.service` | `dbus` |
| `systemd-journald.service` | `systemd-journald` |
| `systemd-dbus.service` | `systemd-dbus` |
| `xvnc.service` | `xvnc` |
| `xfce.service` | `xfce` |
| `novnc.service` | `novnc` |

For any other `.service` file, `systemctl start` parses `ExecStart=`,
`Environment=`, `User=`, `WorkingDirectory=` and `Restart=` and writes a
generated program into `/etc/supervisor/conf.d/`, then runs
`supervisorctl reread && supervisorctl update`.

## Deploying on CranL

See [docs/DEPLOY-CRANL.md](docs/DEPLOY-CRANL.md). The short version:

1. Push this repository to GitHub.
2. Let GitHub Actions build the GHCR image, **or** let CranL build the
   Dockerfile directly from the repository.
3. Create a CranL app with port `3000`, health path `/healthz`, and the
   environment variables above.
4. Open the generated `*.cranl.net` URL.

The free plan allows two apps. Keep the old desktop running until the new app
passes the health check, then delete the old one from the dashboard.

> **CranL status, 23 Oct 2026:** the Edge Server component reports a
> `major_outage`. Ingress to apps still works, but app **egress** (DNS resolves,
> TCP/ICMP times out) is blocked. This is a platform outage, not an image
> problem. Also, CranL app containers cannot activate a swap file; see the
> [Swap](#swap) section. Use a VPS for immediate internet plus active swap.

## GitHub Actions / GHCR

The workflow `.github/workflows/build.yml` builds `linux/amd64` and pushes:

```
ghcr.io/<owner>/ubuntu-systemd-desktop:latest
ghcr.io/<owner>/ubuntu-systemd-desktop:sha-<commit>
```

Make the GHCR package public after the first build, or create a GitHub PAT
with `read:packages` and use it as the CranL registry credential.

## Testing

Inside the container:

```bash
/opt/desktop/tests/smoke-test.sh
sudo /opt/desktop/tests/test-systemd.sh
```

Manual checks:

```bash
systemctl --version
systemctl is-system-running
systemctl status
systemctl status xvnc
systemd-detect-virt
hostnamectl
journalctl -n 20
busctl --system introspect org.freedesktop.systemd1 /org/freedesktop/systemd1
ps -p 1 -o comm=
firefox --version
curl -fsS http://127.0.0.1:3000/healthz
```

See [docs/TESTING.md](docs/TESTING.md) for expected output and browser checks.

## Project layout

```
.
├── Dockerfile
├── docker-compose.yml
├── supervisor/supervisord.conf
├── systemd/
│   ├── systemd_compat.py
│   ├── systemctl.py
│   ├── systemd_dbus.py
│   ├── systemd-journald.py
│   ├── systemd-detect-virt.py
│   ├── hostnamectl.py / timedatectl.py / loginctl.py / journalctl.py
│   ├── units/
│   └── dbus/
├── scripts/                 # startup, desktop setup, health check
├── desktop/                 # wallpaper, Firefox defaults, launchers
├── web/                     # noVNC landing page, welcome page, healthz
├── tests/
├── docs/
└── .github/workflows/build.yml
```

## Known limitations

- **Not real systemd.** PID 1 is Supervisord; there is no systemd manager
  process, no cgroup delegation and no systemd-native socket activation.
- **D-Bus is a facade.** Common Manager/Unit methods work, but advanced
  transaction/job semantics and all properties are not implemented.
- **Container checks can still succeed.** `/.dockerenv` (unless
  `HIDE_CONTAINER=1`), `/proc/1/cgroup`, overlayfs and the Docker network
  remain visible. This project does not attempt to defeat security software,
  anti-cheat or licence enforcement.
- **No snap.** Firefox comes from Mozilla's APT repository instead.
- **No audio device / no GPU acceleration.** It is a VNC desktop.
- **CranL apps cannot activate swap.** `swapon` needs a capability the runtime
  does not grant; `/var/swap/swapfile` is created and reported, but remains
  inactive. A VPS/host with swap enabled is required for active 6 GiB swap.
- **CranL egress is currently down.** The Edge Server reports a major outage;
  apps can be reached from the browser, but they cannot reach the internet.
- **Data is ephemeral.** Files live in the container; redeploys can erase them.
- **Public VNC is sensitive.** Use a strong password and a private URL. TLS is
  terminated at CranL; noVNC uses WSS to the edge.

## Security recommendations

1. Set a strong, unique `VNC_PW` (8 characters maximum) before deployment.
2. Change the `desktop` Linux password after first login.
3. Do not store SSH keys, tokens or personal data in the container.
4. Keep the URL private; anyone with the URL and password has full control.
5. Rebuild regularly to pick up Ubuntu and Firefox security updates.

## License

MIT. See [LICENSE](LICENSE).

---

## البدء السريع بالعربية

1. ارفع المجلد إلى GitHub.
2. شغّل GitHub Actions، أو أنشئ تطبيقًا على CranL من المستودع مع
   `build: dockerfile` والمنفذ `3000`.
3. اضبط `VNC_PW` بكلمة مرور قوية، واترك `NOVNC_PORT=3000`.
4. افتح الرابط، اضغط **Open Desktop**، ثم أدخل كلمة مرور VNC.
5. غيّر كلمة مرور المستخدم `desktop` من داخل الطرفية بالأمر `passwd`.

طبقة systemd هنا **توافقية** وليست systemd الحقيقي؛ راجع قسم القيود أعلاه.
