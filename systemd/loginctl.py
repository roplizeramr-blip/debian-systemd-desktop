#!/usr/bin/env python3
"""loginctl compatibility shim.

The desktop runs inside one container session, so a single synthetic seat and
session are exposed.  This is enough for applications that use loginctl to
discover the current graphical session.
"""
from __future__ import annotations

import os
import pwd
import sys


def user_info() -> tuple[str, int]:
    try:
        entry = pwd.getpwnam("desktop")
        return entry.pw_name, entry.pw_uid
    except KeyError:
        return os.environ.get("USER", "desktop"), os.getuid()


def session_props() -> dict[str, str]:
    user, uid = user_info()
    return {
        "Id": "1",
        "User": user,
        "UID": str(uid),
        "Name": user,
        "Seat": "seat0",
        "TTY": "",
        "Remote": "yes",
        "Service": "lightdm",
        "Type": "x11",
        "Class": "user",
        "Active": "yes",
        "State": "active",
        "Desktop": "xfce",
        "Display": ":1",
    }


def list_sessions(no_legend: bool) -> int:
    user, uid = user_info()
    if not no_legend:
        print(f"{'SESSION':<8} {'UID':<8} {'USER':<16} {'SEAT':<8} TTY")
    print(f"{'1':<8} {uid:<8} {user:<16} {'seat0':<8}")
    if not no_legend:
        print("")
        print("1 sessions listed.")
    return 0


def list_users(no_legend: bool) -> int:
    user, uid = user_info()
    if not no_legend:
        print(f"{'USER':<16} UID")
    print(f"{user:<16} {uid}")
    if not no_legend:
        print("")
        print("1 users listed.")
    return 0


def show_session(session_id: str) -> int:
    props = session_props()
    if session_id not in ("1", "", "auto"):
        print(f"Session {session_id} not found.", file=sys.stderr)
        return 1
    for key, value in props.items():
        print(f"{key}={value}")
    return 0


def show_user() -> int:
    user, uid = user_info()
    props = {
        "UID": str(uid),
        "Name": user,
        "State": "active",
        "Sessions": "1",
        "Display": "1",
        "Linger": "no",
        "Slice": f"user-{uid}.slice",
    }
    for key, value in props.items():
        print(f"{key}={value}")
    return 0


def main(argv: list[str]) -> int:
    no_legend = "--no-legend" in argv
    if "--version" in argv:
        print("systemd 255")
        return 0
    if "--help" in argv or "-h" in argv:
        print("loginctl [OPTIONS...] COMMAND ...")
        print("  list-sessions          List sessions")
        print("  list-users             List users")
        print("  show-session [ID]      Show session properties")
        print("  show-user [USER]       Show user properties")
        print("  terminate-session ID   Terminate a session")
        return 0
    if "list-sessions" in argv:
        return list_sessions(no_legend)
    if "list-users" in argv:
        return list_users(no_legend)
    if "show-session" in argv:
        index = argv.index("show-session")
        session_id = argv[index + 1] if index + 1 < len(argv) else "1"
        return show_session(session_id)
    if "show-user" in argv:
        return show_user()
    if "terminate-session" in argv:
        index = argv.index("terminate-session")
        session_id = argv[index + 1] if index + 1 < len(argv) else "1"
        print(f"Could not terminate session {session_id}: the desktop session is managed by Supervisor.", file=sys.stderr)
        return 1
    if "activate-session" in argv:
        return 0
    if "lock-session" in argv or "unlock-session" in argv:
        return 0
    return list_sessions(no_legend)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
