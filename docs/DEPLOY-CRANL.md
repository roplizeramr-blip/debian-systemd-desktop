# Deploying on CranL

CranL runs the container and exposes HTTPS on a `*.cranl.net` domain.  The app
must listen on the configured port and bind `0.0.0.0`.  This image listens on
`NOVNC_PORT` (default `3000`) and binds `0.0.0.0`; TigerVNC stays on loopback.

## Option A — CranL builds the Dockerfile from GitHub

1. Push this repository to GitHub (public is simplest).
2. In CranL, create an app:
   - Source: GitHub repository
   - Build: Dockerfile
   - Port: `3000`
   - Health check path: `/healthz`
   - Region: `netherlands-1` (free plan)
3. Add environment variables:

| Key | Value |
|---|---|
| `NOVNC_PORT` | `3000` |
| `VNC_PORT` | `5901` |
| `VNC_RESOLUTION` | `1440x900` |
| `VNC_PW` | a strong unique password (maximum 8 characters) |
| `VNC_FRAME_RATE` | `30` |
| `VNC_COMPARE_FB` | `2` |
| `VNC_ZLIB_LEVEL` | `1` |
| `SWAP_ENABLED` | `1` |
| `SWAP_SIZE_MB` | `6144` |
| `SWAP_SPARSE` | `1` (CranL container disk) |
| `TZ` | `Africa/Cairo` |
| `SYSTEMD_DETECT_VIRT` | `none` |
| `HIDE_CONTAINER` | `0` (or `1` only if you accept the caveat) |

4. Deploy and wait for the build.
5. Open `https://<app>-<hash>-<region>.cranl.net`.
6. Confirm `/healthz` returns `200 OK`.

## Option B — GitHub Actions builds to GHCR, CranL pulls the image

1. Push to GitHub.
2. Wait for the **Build and publish container** workflow.
3. The image is:

   ```
   ghcr.io/<owner>/ubuntu-systemd-desktop:latest
   ```

4. Make the GHCR package public:
   GitHub → your profile → Packages → `ubuntu-systemd-desktop` → Package
   settings → Change visibility → Public.

   Or keep it private and create a GitHub PAT with `read:packages`; use it as
   the registry username/password in CranL.
5. In CranL create a Docker-image app:
   - Image: `ghcr.io/<owner>/ubuntu-systemd-desktop:latest`
   - Port: `3000`
   - Health path: `/healthz`
   - Region: `netherlands-1`
   - Same environment variables as above.

## First login

1. Open the app URL.
2. Click **Open Desktop**.
3. Enter `VNC_PW`.
4. Open Terminal and run:

   ```bash
   passwd
   systemctl is-system-running
   systemd-detect-virt
   firefox --version
   ```

## Replacing the old desktop

The free plan allows **two apps**.  Keep the old desktop alive while the new
app builds and passes its health check, then delete the old app.

> **Important:** deleting from the CranL dashboard is immediate and frees the
> slot.  Deleting through the API/MCP keeps the app for 7 days and it still
> counts against the quota.  Use the dashboard when you are ready to remove the
> old desktop permanently.

## Swap and egress on CranL

- **Swap cannot be activated.** CranL app containers do not grant
  `CAP_SYS_ADMIN`; `swapon /var/swap/swapfile` returns `EPERM`. Moving the file
  from `/swapfile` to `/var/swap` does not change this. The image creates the
  file and reports the exact error at `/swap-status.json` and
  `/var/log/swap.log`; it does not pretend the swap is active.
- **Egress is currently blocked.** On 23 Oct 2026 the CranL status endpoint
  reports `major_outage` for the Edge Server. App ingress (the browser URL and
  `/healthz`) still works, but DNS resolves and outbound TCP/ICMP times out.
  Firefox, `apt`, `curl` and GitHub from inside the desktop will not reach the
  internet until CranL repairs the platform.
- **For real swap plus internet, use a VPS.** See
  [DEPLOY-VPS.md](DEPLOY-VPS.md). The host script creates the same 6 GiB file at
  `/var/swap/swapfile` and activates it; the container should run with
  `SWAP_ENABLED=0`.

## Health check

```
GET /healthz  →  200  OK
```

CranL should use this path.  A 502 usually means noVNC/websockify is not
running; check the app logs and `supervisorctl status novnc`.

## Port rules

- The CranL app port must equal `NOVNC_PORT`.
- If the platform injects `PORT`, the entrypoint uses it when `NOVNC_PORT` is
  not explicitly set.  For clarity, set `NOVNC_PORT=3000` explicitly.
- Do not expose `5901`; it is bound to loopback and proxied by websockify.

## Custom domain

The free plan includes the default `*.cranl.net` domain.  Custom domains are
not available on the free plan.  TLS is terminated by CranL; noVNC connects
with WSS to the edge.

## Updating

- GitHub build: push a commit and redeploy.
- GHCR build: push a commit, wait for Actions, redeploy the image.
- Data in the container is ephemeral.  Download important files first.

## Troubleshooting

| Symptom | Check |
|---|---|
| Build fails at Firefox | Mozilla repo/network; retry the build |
| Health 502 | `supervisorctl status novnc`; `/var/log/supervisor/novnc.err.log` |
| Health 200 but black screen | `supervisorctl status xvnc xfce`; check logs |
| `systemctl` degraded | `supervisorctl status`; restart failing program |
| D-Bus errors | `supervisorctl status dbus systemd-dbus` |
| VNC password rejected | `VNC_PW` changed but container not restarted |

## Useful CranL notes

- The app must bind `0.0.0.0`, not `127.0.0.1`, for the public port.
- The default domain can take a short time to resolve after the first deploy.
- Free plan: 2 apps, 1 project, 0 custom domains.
- Use the dashboard for immediate deletion; API/MCP deletion has a 7-day
  retention and still counts against the limit.
