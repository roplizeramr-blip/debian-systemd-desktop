# Deploying on a VPS (internet + real 6 GiB swap)

Use a VPS when you need **both** outbound internet and a swap file that is
actually active. CranL app containers cannot activate swap and, as of
23 Oct 2026, their outbound egress is blocked by the platform outage.

Recommended minimum: 2 vCPU, 4 GiB RAM, 40 GiB disk, Ubuntu 24.04.

## 1. Create the host swap

The swap file lives on the **host**, at `/var/swap/swapfile`, and is therefore
available to every container on that host. Run as root:

```bash
sudo SWAP_SIZE_MB=6144 bash scripts/host-swap.sh
```

Verify:

```bash
swapon --show
free -h
cat /proc/sys/vm/swappiness
```

The helper also adds the swap entry to `/etc/fstab` and writes
`/etc/sysctl.d/99-cloud-desktop-swap.conf` (`vm.swappiness=10`).

## 2. Run the desktop container

The container should **not** create a second swap file when the host already
provides one. Disable its internal swap setup:

```bash
git clone https://github.com/roplizeramr-blip/ubuntu-systemd-desktop.git
cd ubuntu-systemd-desktop

VNC_PW='N7xQ4mK2' \
SWAP_ENABLED=0 \
docker compose up -d --build
```

Or plain Docker:

```bash
docker build -t ubuntu-systemd-desktop .

docker run -d --name ubuntu-desktop \
  --restart unless-stopped \
  -p 3000:3000 \
  --shm-size=1g \
  -e VNC_PW='N7xQ4mK2' \
  -e VNC_RESOLUTION='1440x900' \
  -e VNC_FRAME_RATE='30' \
  -e VNC_ZLIB_LEVEL='1' \
  -e SWAP_ENABLED='0' \
  -e TZ='Africa/Cairo' \
  ubuntu-systemd-desktop
```

Open `http://<vps-ip>:3000`. For a public deployment, put Caddy, Nginx or
Traefik in front with TLS (the desktop itself speaks plain HTTP/WebSocket
inside the host). Do **not** expose port 3000 directly to the internet without
TLS and a firewall.

## 3. Verify

```bash
curl -fsS http://127.0.0.1:3000/healthz
curl -fsS http://127.0.0.1:3000/swap-status.json
docker exec ubuntu-desktop free -h
docker exec ubuntu-desktop pgrep -a Xvnc
```

The VNC status file will show `"active": true` only if the **container** ran
`setup-swap.sh` and was allowed to call `swapon`. With host swap and
`SWAP_ENABLED=0`, check `swapon --show` on the host instead; the container
benefits from the host swap automatically unless the runtime sets a zero swap
limit.

## 4. Performance notes

- Keep the default `1440x900` and `VNC_FRAME_RATE=30` for a remote link.
- On a slow link, lower the resolution to `1280x800` first.
- On a fast LAN, raise `VNC_FRAME_RATE` to `60` and increase noVNC's
  `quality`/`compression` query parameters in `web/index.html`.
- `SWAP_SPARSE=0` on a VPS creates a fully allocated file; a sparse file can be
  rejected by the kernel with `Swapfile has holes`.
- The desktop is CPU-rendered; a VPS with 2 vCPU is enough for XFCE + one
  Firefox window. More vCPUs help browser workloads, not VNC encoding.

## 5. Security

- Use a unique 8-character `VNC_PW`; it is the only VNC authentication factor.
- Change the Linux password (`passwd`) and do not expose SSH unnecessarily.
- Put TLS in front; noVNC over plain HTTP leaks keystrokes and the VNC password.
- The container's data is ephemeral. Mount a volume for `/home/desktop` if you
  need persistence.
