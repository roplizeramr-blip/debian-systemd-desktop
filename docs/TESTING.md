# Testing

## 1. Build

```bash
docker compose build
docker compose up -d
docker compose logs -f --tail=100
```

The first boot can take 30–60 seconds while XFCE starts.

## 2. Automated smoke test

```bash
docker compose exec desktop /opt/desktop/tests/smoke-test.sh
```

Expected: every line `PASS`, final `Failed: 0` (the swap-active line may be
`WARN` on CranL; that is expected and does not fail the test).

### Performance and swap checks

```bash
pgrep -a Xvnc | grep -E 'FrameRate|ZlibLevel|CompressLevel|noreset'
pgrep -a earlyoom
cat /var/log/swap.log
cat /usr/share/novnc/swap-status.json
/usr/local/bin/swap-status.sh
/usr/local/bin/system-status.sh
```

On CranL the status JSON should show `"active": false` with an `EPERM`
message; the file is created but the container runtime blocks `swapon`. On a
VPS with `SWAP_ENABLED=0` and host swap, `swapon --show` on the host is the
source of truth.

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
systemctl status xvnc.service
systemctl is-active xvnc.service
systemctl is-enabled xfce.service
systemctl list-units --type=service
systemctl list-unit-files --type=service
systemctl show xvnc.service -p ActiveState,SubState,MainPID
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
- `systemctl is-active xvnc.service` → `active`
- `hostnamectl` contains `Ubuntu 24.04`
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

## 6. Browser checks

1. Open `http://localhost:3000`.
2. The landing page should show **Desktop ready**.
3. Click **Open Desktop**.
4. Enter the VNC password.
5. Confirm:
   - XFCE panel and desktop icons are visible.
   - The wallpaper is the custom blue "Ubuntu Cloud Desktop" image.
   - Firefox opens and shows the welcome page.
   - Terminal opens.
   - `Systemd Compatibility Info` launches and prints status.
   - `System Dashboard` shows memory, swap, services and VNC processes.
6. Resize the browser; noVNC should scale the desktop (`resize=remote`).
7. The landing page should show **Swap: file ready (not active)** on CranL.
   That is the honest container limitation, not a failed build.
8. Close the browser tab, reopen the URL and reconnect. The XFCE session
   should still be there (`-noreset`), instead of a fresh desktop.

## 7. Health endpoint

```bash
curl -i http://127.0.0.1:3000/healthz
# HTTP/1.1 200 OK
# OK
```

## 8. Common failures

| Symptom | Cause | Fix |
|---|---|---|
| Landing page 502 | websockify not running | `supervisorctl status novnc`, check `/var/log/supervisor/novnc.err.log` |
| VNC "connection refused" | Xvnc not ready | `supervisorctl status xvnc`, check `/var/log/supervisor/xvnc.err.log` |
| Black screen | XFCE failed | `supervisorctl restart xfce`, check `xfce.err.log` |
| Firefox fails to start | sandbox/shm | increase `shm_size`; check `firefox --version`; use `--no-sandbox` only for diagnosis |
| `systemctl` says degraded | core program failed | `supervisorctl status`; check the failing log |
| D-Bus introspection fails | system bus or service not ready | `supervisorctl status dbus systemd-dbus`; restart `systemd-dbus` |
