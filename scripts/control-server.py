#!/usr/bin/env python3
"""Small public control plane for the KasmVNC + Tailscale desktop.

The public CranL port only serves this page, its JSON status API, and a
health probe.  The desktop itself listens on loopback and is reachable only
through Tailscale Serve.  Keeping this process deliberately small avoids a
second web framework and keeps the image fast.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

APP_ROOT = Path(os.environ.get("DESKTOP_APP_ROOT", "/opt/desktop"))
WEB_INDEX = Path(os.environ.get("DESKTOP_WEB_INDEX", str(APP_ROOT / "web" / "index.html")))
KASM_HOST = os.environ.get("KASM_HOST", "127.0.0.1")
KASM_PORT = int(os.environ.get("KASM_PORT", "6080"))
CONTROL_PORT = int(os.environ.get("CONTROL_PORT") or os.environ.get("PORT") or "3000")
TS_SOCKET = os.environ.get("TS_SOCKET", "").strip()
TS_HOSTNAME = os.environ.get("TS_HOSTNAME", "ubuntu-desktop").strip() or "ubuntu-desktop"
TS_SERVE_HTTPS_PORT = int(os.environ.get("TS_SERVE_HTTPS_PORT", "443"))
TS_SERVE_HTTP_PORT = int(os.environ.get("TS_SERVE_HTTP_PORT", "0"))
TS_FUNNEL = os.environ.get("TS_FUNNEL", "0") != "0"
SERVE_HTTP_FLAG = Path("/run/desktop-tailscale-http.ok")
SERVE_HTTPS_FLAG = Path("/run/desktop-tailscale-https.ok")
LOGIN_LOG = Path("/tmp/tailscale-login.log")
LOGIN_URL_RE = re.compile(r"https://login\.tailscale\.com/a/[A-Za-z0-9_-]+")

TAILSCALE = shutil.which("tailscale") or "/usr/bin/tailscale"
LOGIN_LOCK = threading.Lock()
LOGIN_PROC: subprocess.Popen[str] | None = None
LOGIN_URL: str | None = None


def _json_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def _run_ts(args: list[str], timeout: float = 5.0) -> subprocess.CompletedProcess[str] | None:
    if not Path(TAILSCALE).exists():
        return None
    command = [TAILSCALE]
    if TS_SOCKET:
        command.extend(["--socket", TS_SOCKET])
    command.extend(args)
    try:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            env={**os.environ, "HOME": "/root"},
        )
    except (OSError, subprocess.SubprocessError):
        return None


def tailscale_status() -> dict[str, object] | None:
    result = _run_ts(["status", "--json"], timeout=4.0)
    if result is None or result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        parsed = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def desktop_ready() -> bool:
    try:
        with socket.create_connection((KASM_HOST, KASM_PORT), timeout=0.45):
            return True
    except OSError:
        return False


def _flag(path: Path) -> bool:
    try:
        return path.is_file()
    except OSError:
        return False


def _login_url_from_log() -> str | None:
    try:
        text = LOGIN_LOG.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    match = LOGIN_URL_RE.search(text)
    return match.group(0) if match else None


def _status_details() -> dict[str, object]:
    global LOGIN_URL

    status = tailscale_status()
    backend_state = "Unavailable"
    online = False
    ipv4: str | None = None
    dns_name: str | None = None
    login_url: str | None = None

    if status is not None:
        backend_state = str(status.get("BackendState") or "Unknown")
        self_info = status.get("Self")
        if isinstance(self_info, dict):
            addresses = self_info.get("TailscaleIPs") or []
            if isinstance(addresses, list):
                ipv4 = next((str(item) for item in addresses if ":" not in str(item)), None)
            dns_name = str(self_info.get("DNSName") or "").rstrip(".") or None
        raw_login = status.get("AuthURL")
        if isinstance(raw_login, str) and raw_login.startswith("https://"):
            login_url = raw_login
        online = backend_state == "Running" and bool(ipv4)

    if not login_url:
        login_url = LOGIN_URL or _login_url_from_log()

    http_ready = _flag(SERVE_HTTP_FLAG)
    https_ready = _flag(SERVE_HTTPS_FLAG)

    http_url = None
    if http_ready and ipv4 and TS_SERVE_HTTP_PORT:
        http_url = f"http://{ipv4}:{TS_SERVE_HTTP_PORT}/"
    https_url = None
    if https_ready and dns_name and TS_SERVE_HTTPS_PORT:
        suffix = "" if TS_SERVE_HTTPS_PORT == 443 else f":{TS_SERVE_HTTPS_PORT}"
        https_url = f"https://{dns_name}{suffix}/"

    # The Tailscale link (MagicDNS name over HTTPS) is the primary path so the
    # raw Tailscale IP and its ports stay free for other apps on the same node.
    # The IP-based URL is only a fallback when the raw TCP rule is enabled.
    open_url = https_url or http_url
    ready = bool(online and desktop_ready() and open_url)

    return {
        "ready": ready,
        "desktop": {
            "running": desktop_ready(),
            "engine": "KasmVNC",
            "host": KASM_HOST,
            "port": KASM_PORT,
            "auth": os.environ.get("VNC_AUTH", "1") != "0",
            "user": os.environ.get("VNC_USER", "desktop"),
        },
        "tailscale": {
            "installed": Path(TAILSCALE).exists(),
            "backend_state": backend_state,
            "online": online,
            "hostname": TS_HOSTNAME,
            "ipv4": ipv4,
            "dns_name": dns_name,
            "login_url": None if online else login_url,
            "serve_http": http_ready,
            "serve_https": https_ready,
            "funnel": TS_FUNNEL,
            "http_port": TS_SERVE_HTTP_PORT,
            "https_port": TS_SERVE_HTTPS_PORT,
        },
        "urls": {
            "open": open_url,
            "http": http_url,
            "https": https_url,
        },
    }


def _start_login_locked() -> dict[str, object]:
    global LOGIN_PROC, LOGIN_URL

    # The Supervisor program for tailscaled may still be starting when the user
    # clicks Connect immediately after the page loads. Give the daemon a short
    # window to answer before launching tailscale up.
    wait_until = time.monotonic() + 12.0
    while time.monotonic() < wait_until:
        if tailscale_status() is not None:
            break
        time.sleep(0.5)

    details = _status_details()
    tailscale = details["tailscale"]
    if tailscale["online"]:
        return {"ok": True, "mode": "already-online", "status": details}

    if not Path(TAILSCALE).exists():
        return {"ok": False, "error": "Tailscale is not installed"}

    if not LOGIN_PROC or LOGIN_PROC.poll() is not None:
        LOGIN_PROC = None
        LOGIN_URL = None
        try:
            LOGIN_LOG.unlink()
        except OSError:
            pass

        authkey = os.environ.get("TS_AUTHKEY", "").strip()
        args = [TAILSCALE]
        if TS_SOCKET:
            args.extend(["--socket", TS_SOCKET])
        args.extend(
            [
                "up",
                "--hostname",
                TS_HOSTNAME,
                "--accept-dns=false",
                "--ssh=false",
            ]
        )
        if authkey:
            args.append(f"--auth-key={authkey}")

        try:
            with LOGIN_LOG.open("w", encoding="utf-8") as log_file:
                LOGIN_PROC = subprocess.Popen(
                    args,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    stdin=subprocess.DEVNULL,
                    text=True,
                    start_new_session=True,
                    env={**os.environ, "HOME": "/root"},
                )
        except OSError as exc:
            LOGIN_PROC = None
            return {"ok": False, "error": f"Could not start Tailscale login: {exc}"}

        if authkey:
            return {
                "ok": True,
                "mode": "auth-key",
                "message": "Tailscale is connecting with TS_AUTHKEY.",
                "status": _status_details(),
            }

    deadline = time.monotonic() + 18.0
    while time.monotonic() < deadline:
        LOGIN_URL = _login_url_from_log()
        if not LOGIN_URL:
            status = tailscale_status()
            if status:
                candidate = status.get("AuthURL")
                if isinstance(candidate, str) and candidate.startswith("https://"):
                    LOGIN_URL = candidate
        if LOGIN_URL:
            return {
                "ok": True,
                "mode": "browser",
                "login_url": LOGIN_URL,
                "status": _status_details(),
            }
        if LOGIN_PROC is not None and LOGIN_PROC.poll() is not None:
            break
        time.sleep(0.35)

    try:
        log_tail = LOGIN_LOG.read_text(encoding="utf-8", errors="replace")[-1200:]
    except OSError:
        log_tail = ""
    return {
        "ok": False,
        "error": "Tailscale did not return a login URL yet.",
        "detail": log_tail,
        "status": _status_details(),
    }


def start_login() -> dict[str, object]:
    # Serialize clicks so repeated presses cannot launch several login daemons.
    with LOGIN_LOCK:
        return _start_login_locked()


class Handler(BaseHTTPRequestHandler):
    server_version = "UbuntuDesktopControl/1.0"
    sys_version = ""

    def log_message(self, fmt: str, *args: object) -> None:
        # Keep supervisor logs useful without logging every browser poll.
        if self.path not in ("/api/status", "/healthz", "/favicon.ico"):
            super().log_message(fmt, *args)

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; img-src 'self' data:; style-src 'unsafe-inline'; "
            "script-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; "
            "base-uri 'none'; form-action 'self'",
        )
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _send_json(self, status: int, payload: object) -> None:
        self._send(status, _json_bytes(payload), "application/json; charset=utf-8")

    def _index(self) -> bytes:
        try:
            return WEB_INDEX.read_bytes()
        except OSError:
            return b"Ubuntu Cloud Desktop control page is missing.\n"

    def do_HEAD(self) -> None:  # noqa: N802 - stdlib callback name
        self.do_GET()

    def do_GET(self) -> None:  # noqa: N802 - stdlib callback name
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            if desktop_ready():
                self._send(200, b"ok\n", "text/plain; charset=utf-8")
            else:
                self._send(503, b"desktop-starting\n", "text/plain; charset=utf-8")
            return
        if path == "/api/status":
            self._send_json(200, {"ok": True, "status": _status_details()})
            return
        if path == "/robots.txt":
            self._send(200, b"User-agent: *\nDisallow: /\n", "text/plain; charset=utf-8")
            return
        if path == "/favicon.ico":
            self._send(204, b"", "image/x-icon")
            return
        if path == "/":
            self._send(200, self._index(), "text/html; charset=utf-8")
            return
        self._send(404, b"not found\n", "text/plain; charset=utf-8")

    def do_POST(self) -> None:  # noqa: N802 - stdlib callback name
        path = self.path.split("?", 1)[0]
        if path != "/api/tailscale/connect":
            self._send(404, b"not found\n", "text/plain; charset=utf-8")
            return

        # Do not read request bodies.  The endpoint has no user-controlled
        # arguments and only starts the normal Tailscale browser login.
        content_length = self.headers.get("Content-Length", "0")
        try:
            remaining = min(int(content_length), 65536)
        except ValueError:
            remaining = 0
        if remaining > 0:
            self.rfile.read(remaining)

        try:
            payload = start_login()
        except Exception as exc:  # keep the public endpoint from crashing the server
            self._send_json(500, {"ok": False, "error": str(exc)})
            return
        self._send_json(200 if payload.get("ok") else 502, payload)


class Server(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> None:
    server = Server(("0.0.0.0", CONTROL_PORT), Handler)
    print(
        f"[control] public page on 0.0.0.0:{CONTROL_PORT}; "
        f"KasmVNC on {KASM_HOST}:{KASM_PORT}",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
