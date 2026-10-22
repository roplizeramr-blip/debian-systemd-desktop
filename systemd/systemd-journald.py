#!/usr/bin/env python3
"""A small journald-compatible socket sink.

It accepts the standard journal datagram sockets plus the stdout stream
socket and writes everything to /var/log/journal/compat.log.  journalctl.py
reads that file and the Supervisor logs.
"""
from __future__ import annotations

import os
import select
import socket
import sys
import threading
import time
from pathlib import Path

JOURNAL_DIR = Path("/run/systemd/journal")
LOG_PATH = Path("/var/log/journal/compat.log")
DATAGRAM_PATHS = [JOURNAL_DIR / "socket", JOURNAL_DIR / "dev-log"]
STREAM_PATH = JOURNAL_DIR / "stdout"


def write_line(prefix: str, payload: bytes) -> None:
    text = payload.decode("utf-8", errors="replace").rstrip("\n")
    if not text:
        return
    timestamp = time.strftime("%b %d %H:%M:%S")
    host = socket.gethostname()
    line = f"{timestamp} {host} {prefix}: {text}\n"
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as handle:
            handle.write(line)
    except OSError as exc:
        print(f"journald-shim: cannot write log: {exc}", file=sys.stderr)


def handle_stream(connection: socket.socket, address: object) -> None:
    with connection:
        while True:
            try:
                data = connection.recv(8192)
            except OSError:
                break
            if not data:
                break
            write_line("stdout", data)


def unlink_socket(path: Path) -> None:
    try:
        if path.exists() or path.is_symlink():
            path.unlink()
    except OSError:
        pass


def main() -> int:
    JOURNAL_DIR.mkdir(parents=True, exist_ok=True)
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    try:
        LOG_PATH.touch(exist_ok=True)
    except OSError:
        pass

    datagrams: list[socket.socket] = []
    for path in DATAGRAM_PATHS:
        unlink_socket(path)
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        try:
            sock.bind(str(path))
        except OSError as exc:
            print(f"journald-shim: cannot bind {path}: {exc}", file=sys.stderr)
            sock.close()
            continue
        os.chmod(path, 0o666)
        datagrams.append(sock)

    unlink_socket(STREAM_PATH)
    stream = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        stream.bind(str(STREAM_PATH))
        os.chmod(STREAM_PATH, 0o666)
        stream.listen(16)
    except OSError as exc:
        print(f"journald-shim: cannot bind {STREAM_PATH}: {exc}", file=sys.stderr)
        stream.close()
        stream = None  # type: ignore[assignment]

    readables: list[socket.socket] = list(datagrams)
    if stream is not None:
        readables.append(stream)

    try:
        while True:
            try:
                ready, _, _ = select.select(readables, [], [], 1.0)
            except InterruptedError:
                continue
            for sock in ready:
                if sock is stream:
                    try:
                        connection, address = stream.accept()
                    except OSError:
                        continue
                    threading.Thread(
                        target=handle_stream,
                        args=(connection, address),
                        daemon=True,
                    ).start()
                else:
                    try:
                        payload = sock.recv(65536)
                    except OSError:
                        continue
                    write_line(sock.getsockname().rsplit("/", 1)[-1], payload)
    except KeyboardInterrupt:
        pass
    finally:
        for sock in readables:
            try:
                sock.close()
            except OSError:
                pass
        for path in DATAGRAM_PATHS + [STREAM_PATH]:
            unlink_socket(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
