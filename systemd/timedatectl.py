#!/usr/bin/env python3
"""timedatectl compatibility shim."""
from __future__ import annotations

import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def current_zone() -> str:
    try:
        text = Path("/etc/timezone").read_text(encoding="utf-8").strip()
        if text:
            return text
    except OSError:
        pass
    env = os.environ.get("TZ", "")
    if env:
        return env
    try:
        target = os.readlink("/etc/localtime")
        marker = "/zoneinfo/"
        if marker in target:
            return target.split(marker, 1)[1]
    except OSError:
        pass
    return "Etc/UTC"


def status() -> int:
    zone = current_zone()
    try:
        tz = ZoneInfo(zone)
    except ZoneInfoNotFoundError:
        tz = timezone.utc
    local = datetime.now(tz)
    universal = datetime.now(timezone.utc)
    offset = local.strftime("%z")
    zone_abbr = local.strftime("%Z")
    print(f"      Local time: {local.strftime('%a %Y-%m-%d %H:%M:%S %Z')}")
    print(f"  Universal time: {universal.strftime('%a %Y-%m-%d %H:%M:%S UTC')}")
    print(f"        RTC time: {universal.strftime('%a %Y-%m-%d %H:%M:%S')}")
    print(f"       Time zone: {zone} ({zone_abbr}, {offset[:3]}:{offset[3:]})")
    print(" System clock synchronized: yes")
    print("              NTP service: active")
    print("          RTC in local TZ: no")
    return 0


def set_timezone(zone: str) -> int:
    if not zone or not Path("/usr/share/zoneinfo", zone).is_file():
        print(f"Failed to set time zone: Invalid time zone '{zone}'.", file=sys.stderr)
        return 1
    try:
        Path("/etc/timezone").write_text(zone + "\n", encoding="utf-8")
        link = Path("/etc/localtime")
        try:
            link.unlink()
        except FileNotFoundError:
            pass
        link.symlink_to(Path("/usr/share/zoneinfo") / zone)
        os.environ["TZ"] = zone
        time.tzset()
    except OSError as exc:
        print(f"Failed to set time zone: {exc}", file=sys.stderr)
        return 1
    return 0


def list_timezones() -> int:
    root = Path("/usr/share/zoneinfo")
    if not root.is_dir():
        return 0
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if relative.startswith(("posix/", "right/", "Etc/")) or relative in (
            "posixrules",
            "leapseconds",
            "iso3166.tab",
            "zone.tab",
            "zone1970.tab",
            "tzdata.zi",
        ):
            continue
        print(relative)
    return 0


def main(argv: list[str]) -> int:
    if "--version" in argv:
        print("systemd 255")
        return 0
    if "--help" in argv or "-h" in argv:
        print("timedatectl [OPTIONS...] COMMAND ...")
        print("  status                 Show current time settings")
        print("  set-timezone ZONE      Set the system time zone")
        print("  set-ntp BOOL           Enable or disable network time")
        print("  list-timezones         List known time zones")
        return 0
    if "set-timezone" in argv:
        index = argv.index("set-timezone")
        if index + 1 >= len(argv):
            print("Failed to set time zone: missing argument.", file=sys.stderr)
            return 1
        return set_timezone(argv[index + 1])
    if "set-ntp" in argv:
        index = argv.index("set-ntp")
        value = argv[index + 1] if index + 1 < len(argv) else ""
        print(f"NTP service is managed by the host; requested state: {value or 'unknown'}.")
        return 0
    if "set-time" in argv:
        print("Failed to set time: the container clock is managed by the host.", file=sys.stderr)
        return 1
    if "list-timezones" in argv:
        return list_timezones()
    return status()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
