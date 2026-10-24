# Testing

## 1. Build

```bash
docker compose build
docker compose up -d
docker compose logs -f --tail=100
```

The first boot installs nothing extra; allow 30–90 seconds for KasmVNC, XFCE and
tailscaled to start. The control page may show “setup required” until Tailscale
is linked.

## 2. Automated smoke test

```bash
docker compose exec desktop /opt/desktop/tests/smoke-test.sh
```

Expected: every line `PASS`, final `Failed: 0`. Tailscale may legitimately be in
`NeedsLogin`; that does not fail the base smoke test. Swap is disabled by
default, so its checks are skipped.

### Runtime checks

```bash
pgrep -a Xvnc
pgrep -a earlyoom
supervisorctl status
cat /var/log/supervisor/kasmvnc.err.log
cat /var/log/supervisor/tailscaled.err.log
tailscale status
tailscale serve status
curl -i http://127.0.0.1:3000/healthz
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:6080/   # 401 expected
```

If `SWAP_ENABLED=1`:

```bash
cat /run/desktop-swap-status.json
/usr/local/bin/swap-status.sh
```

On CranL the status JSON should show `"active": false` with an `EPERM` message;
the file is created but the container runtime blocks `swapon`. On a VPS with
`SWAP_ENABLED=0` and host swap, `swapon --show` on the host is the source of
truth.

## 3. Dynamic unit test (root)

```bash
docker compose exec -u root desktop /opt/desktop/tests/test-systemd.sh
```

This creates a temporary `compat-test.service`, starts/stops it through
Supervisor, and verifies enable/disable.

## 4. systemd checks

Inside the desktop terminal:

```bash
systemctl --version
systemctl is-system-running
systemctl status
systemctl status kasmvnc.service
systemctl status tailscaled.service
systemctl is-active kasmvnc.service
systemctl is-active control.service
systemctl is-enabled xfce.service
systemctl list-units --type=service
systemctl list-unit-files --type=service
systemctl show kasmvnc.service -p ActiveState,SubState,MainPID
systemd-detect-virt
hostnamectl
timedatectl
loginctl
journalctl -n 20 --no-pager
ps -p 1 -o comm=,args=
test -d /run/systemd/system && echo "sd_booted=yes"
```

Expected highlights:

- `systemctl is-system-running` → `running`
- `systemd-detect-virt` → `none`
- `ps -p 1 -o comm=` → `systemd`
- `systemctl is-active kasmvnc.service` → `active`
- `systemctl is-active tailscaled.service` → `active`
- `hostnamectl` contains `Debian GNU/Linux 13`
- `/run/systemd/system` exists

## 5. D-Bus checks

```bash
busctl --system list-names | grep org.freedesktop.systemd1
busctl --system introspect org.freedesktop.systemd1 /org/freedesktop/systemd1
busctl --system call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
  org.freedesktop.DBus.Properties Get ss \
  org.freedesktop.systemd1.Manager Version
```

The last command should return a variant containing `255`.

You can also use `gdbus`:

```bash
gdbus introspect --system --dest org.freedesktop.systemd1 \
  --object-path /org/freedesktop/systemd1
```

## 6. Tailscale and browser checks

1. Open `http://localhost:3000` or the public CranL URL.
2. The page should show the control/status UI; no desktop is served publicly.
3. Click **Connect Tailscale**; approve the login link in the new tab.
4. Wait until the Tailscale card shows **Connected** and an IP appears.
5. Click **Open VNC**; enter user `desktop` and `VNC_PW`.
6. Confirm:
   - XFCE panel and desktop icons are visible.
   - The wallpaper is the custom blue “Debian Cloud Desktop” image.
   - Google Chrome opens and shows the welcome page.
   - Terminal opens.
   - `Systemd Compatibility Info` launches and prints status.
   - `System Dashboard` shows memory, swap, services and VNC/Tailscale state.
7. Resize the browser; KasmVNC should resize the desktop dynamically.
8. Close the browser tab, reopen the Tailscale URL and reconnect. The XFCE
   session should still be there (KasmVNC keeps the display alive).
9. **Open VNC** should point at the Tailscale MagicDNS link
   (`https://<host>.<tailnet>.ts.net/`), not at a raw-IP port. Confirm the raw
   Tailscale IP stays free (no serve rule bound to it) when
   `TS_SERVE_HTTP_PORT=0`.

## 7. Health endpoint

```bash
curl -i http://127.0.0.1:3000/healthz
# HTTP/1.1 200 OK
# ok
```

## 8. Common failures

| Symptom | Cause | Fix |
|---|---|---|
| Public page 502 | control server not running | `supervisorctl status control`; `/var/log/supervisor/control.err.log` |
| Control page loads, Open VNC disabled | Tailscale not linked or Serve rule not applied | `tailscale status`; `tailscale serve status`; `/var/log/supervisor/tailscale-serve.log` |
| Tailscale login link missing | daemon still starting or `tailscale up` failed | `tailscale status --json`; `/tmp/tailscale-login.log` |
| VNC connection refused | KasmVNC not ready | `supervisorctl status kasmvnc`; `kasmvnc.err.log` |
| Black screen | XFCE failed | `supervisorctl restart xfce`; `xfce.err.log` |
| KasmVNC 401 in container | Expected unauthenticated response | Use `-u desktop:VNC_PW`; this is not an error |
| KasmVNC does not start | missing `.kasmpasswd` or unreadable snakeoil key | check `entrypoint` log; `desktop` must be in `ssl-cert` |
| Chrome fails to start | sandbox/shm | increase `shm_size`; check `google-chrome --version`; the image already passes `--no-sandbox` (see `CHROME_NO_SANDBOX`) |
| `systemctl` says degraded | core program failed | `supervisorctl status`; check the failing log |
| D-Bus introspection fails | system bus or service not ready | `supervisorctl status dbus systemd-dbus`; restart `systemd-dbus` |
