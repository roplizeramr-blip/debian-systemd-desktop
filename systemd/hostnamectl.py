#!/usr/bin/env python3
"""hostnamectl compatibility shim."""
from __future__ import annotations

import json
import os
import platform
import socket
import subprocess
import sys
from pathlib import Path


def read_first(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def os_release() -> dict[str, str]:
    data: dict[str, str] = {}
    try:
        for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.startswith("#"):
                key, value = line.split("=", 1)
                data[key] = value.strip().strip('"')
    except OSError:
        pass
    return data


def values() -> dict[str, str]:
    release = os_release()
    return {
        "Static hostname": read_first("/etc/hostname") or socket.gethostname(),
        "Transient hostname": socket.gethostname(),
        "Pretty hostname": read_first("/etc/machine-info").split("PRETTY_HOSTNAME=")[-1].strip('"') if read_first("/etc/machine-info") else socket.gethostname(),
        "Icon name": "computer-vm",
        "Chassis": "vm",
        "Machine ID": read_first("/etc/machine-id"),
        "Boot ID": read_first("/proc/sys/kernel/random/boot_id"),
        "Virtualization": os.environ.get("SYSTEMD_DETECT_VIRT", "none"),
        "Operating System": release.get("PRETTY_NAME", "Debian GNU/Linux 13 (trixie)"),
        "Kernel": f"Linux {platform.release()}",
        "Architecture": platform.machine().replace("x86_64", "x86-64"),
    }


def status() -> None:
    data = values()
    for key, value in data.items():
        print(f"{key:>20}: {value}")


def json_output(short: bool) -> None:
    data = values()
    mapping = {
        "Static hostname": "hostname",
        "Transient hostname": "transient-hostname",
        "Pretty hostname": "pretty-hostname",
        "Icon name": "icon-name",
        "Chassis": "chassis",
        "Machine ID": "machine-id",
        "Boot ID": "boot-id",
        "Virtualization": "virtualization",
        "Operating System": "operating-system",
        "Kernel": "kernel",
        "Architecture": "architecture",
    }
    result = {mapping.get(key, key): value for key, value in data.items()}
    print(json.dumps(result, ensure_ascii=False, indent=None if short else 2))


def set_hostname(value: str) -> int:
    if not value:
        print("Failed to set hostname: empty name.", file=sys.stderr)
        return 1
    try:
        Path("/etc/hostname").write_text(value + "\n", encoding="utf-8")
    except OSError as exc:
        print(f"Failed to write /etc/hostname: {exc}", file=sys.stderr)
        return 1
    try:
        subprocess.run(["hostname", value], check=False, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return 0


def main(argv: list[str]) -> int:
    if "--version" in argv:
        print("systemd 255")
        return 0
    if "--help" in argv or "-h" in argv:
        print("hostnamectl [OPTIONS...] COMMAND ...")
        print("  status                 Show hostname information")
        print("  set-hostname NAME      Set the system hostname")
        print("  --json=short|pretty    Show machine-readable output")
        return 0

    if "set-hostname" in argv:
        index = argv.index("set-hostname")
        if index + 1 >= len(argv):
            print("Failed to set hostname: missing argument.", file=sys.stderr)
            return 1
        return set_hostname(argv[index + 1])

    for item in argv:
        if item.startswith("--json="):
            mode = item.split("=", 1)[1]
            json_output(mode == "short")
            return 0

    if "--static" in argv:
        print(values()["Static hostname"])
        return 0
    if "--transient" in argv:
        print(values()["Transient hostname"])
        return 0
    if "--pretty" in argv:
        print(values()["Pretty hostname"])
        return 0
    if "--hostname" in argv:
        print(values()["Static hostname"] + " " + values()["Transient hostname"])
        return 0

    status()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
