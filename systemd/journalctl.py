#!/usr/bin/env python3
"""journalctl compatibility shim backed by the Supervisor and journald logs."""
from __future__ import annotations

import glob
import os
import sys
import time
from pathlib import Path

LOG_PATH = Path("/var/log/journal/compat.log")
SUPERVISOR_DIR = Path("/var/log/supervisor")


def parse_args(argv: list[str]) -> dict[str, object]:
    options: dict[str, object] = {
        "units": [],
        "lines": 1000,
        "follow": False,
        "no_pager": False,
        "disk_usage": False,
        "list_boots": False,
        "header": False,
        "fields": False,
        "grep": None,
        "identifier": None,
        "since": None,
        "until": None,
        "priority": None,
        "output": "short",
    }
    i = 0
    while i < len(argv):
        token = argv[i]
        if token in ("-u", "--unit"):
            if i + 1 < len(argv):
                options["units"].append(argv[i + 1])
                i += 2
                continue
        if token.startswith("--unit="):
            options["units"].append(token.split("=", 1)[1])
        elif token in ("-n", "--lines"):
            if i + 1 < len(argv):
                try:
                    options["lines"] = int(argv[i + 1])
                except ValueError:
                    pass
                i += 2
                continue
        elif token.startswith("--lines="):
            try:
                options["lines"] = int(token.split("=", 1)[1])
            except ValueError:
                pass
        elif token in ("-f", "--follow"):
            options["follow"] = True
        elif token == "--no-pager":
            options["no_pager"] = True
        elif token == "--disk-usage":
            options["disk_usage"] = True
        elif token == "--list-boots":
            options["list_boots"] = True
        elif token == "--header":
            options["header"] = True
        elif token in ("--fields", "-N"):
            options["fields"] = True
        elif token in ("-g", "--grep"):
            if i + 1 < len(argv):
                options["grep"] = argv[i + 1]
                i += 2
                continue
        elif token in ("-t", "--identifier"):
            if i + 1 < len(argv):
                options["identifier"] = argv[i + 1]
                i += 2
                continue
        elif token in ("--since", "--until"):
            if i + 1 < len(argv):
                options[token.lstrip("-")] = argv[i + 1]
                i += 2
                continue
        elif token in ("-p", "--priority"):
            if i + 1 < len(argv):
                options["priority"] = argv[i + 1]
                i += 2
                continue
        elif token in ("-o", "--output"):
            if i + 1 < len(argv):
                options["output"] = argv[i + 1]
                i += 2
                continue
        i += 1
    return options


def log_files() -> list[Path]:
    files: list[Path] = []
    if LOG_PATH.is_file():
        files.append(LOG_PATH)
    for path in sorted(SUPERVISOR_DIR.glob("*.log")):
        files.append(path)
    return files


def read_lines(options: dict[str, object]) -> list[str]:
    units = [str(unit).replace(".service", "") for unit in options.get("units", [])]  # type: ignore[arg-type]
    identifier = options.get("identifier")
    grep = options.get("grep")
    lines: list[str] = []
    for path in log_files():
        try:
            content = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in content:
            if units and not any(
                unit in line or path.name.startswith(unit) for unit in units
            ):
                continue
            if identifier and str(identifier) not in line and not path.name.startswith(str(identifier)):
                continue
            if grep and str(grep).lower() not in line.lower():
                continue
            lines.append(line)
    return lines


def disk_usage() -> int:
    total = 0
    for path in log_files():
        try:
            total += path.stat().st_size
        except OSError:
            pass
    print(f"Archived and active journals take up {total} bytes.")
    return 0


def main(argv: list[str]) -> int:
    if "--version" in argv:
        print("systemd 255")
        return 0
    if "--help" in argv or "-h" in argv:
        print("journalctl [OPTIONS...] [MATCHES...]")
        print("  -u, --unit UNIT       Show logs for a unit")
        print("  -n, --lines N         Show the last N lines")
        print("  -f, --follow          Follow new log entries")
        print("  --disk-usage          Show journal disk usage")
        print("  --list-boots          List boot IDs")
        return 0
    options = parse_args(argv)
    if options["disk_usage"]:
        return disk_usage()
    if options["list_boots"]:
        print("IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY")
        boot_id = ""
        try:
            boot_id = Path("/proc/sys/kernel/random/boot_id").read_text(encoding="utf-8").strip()
        except OSError:
            pass
        print(f"  0 {boot_id} -                           -")
        return 0
    if options["fields"]:
        for field in (
            "MESSAGE",
            "PRIORITY",
            "SYSLOG_IDENTIFIER",
            "_PID",
            "_UID",
            "_GID",
            "_COMM",
            "_SYSTEMD_UNIT",
            "_HOSTNAME",
            "_BOOT_ID",
            "_MACHINE_ID",
        ):
            print(field)
        return 0
    if options["header"]:
        print("File: /var/log/journal/compat.log")
        print(f"Hostname: {os.uname().nodename if hasattr(os, 'uname') else 'debian-desktop'}")
        print("Boot ID: " + _read_boot_id())
        return 0

    lines = read_lines(options)
    count = int(options.get("lines") or 0)
    if count > 0:
        lines = lines[-count:]
    if not options["no_pager"]:
        print(f"-- Logs begin at {time.strftime('%a %Y-%m-%d %H:%M:%S %Z')} --")
    for line in lines:
        print(line)
    if not lines:
        print("-- No entries --")
    if options["follow"]:
        seen = len(lines)
        try:
            while True:
                time.sleep(1)
                updated = read_lines(options)
                for line in updated[seen:]:
                    print(line, flush=True)
                seen = len(updated)
        except KeyboardInterrupt:
            pass
    return 0


def _read_boot_id() -> str:
    try:
        return Path("/proc/sys/kernel/random/boot_id").read_text(encoding="utf-8").strip()
    except OSError:
        return ""


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
