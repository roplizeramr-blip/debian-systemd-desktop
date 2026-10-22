#!/usr/bin/env python3
"""systemd-detect-virt compatibility shim.

The default answer is "none", which is what a native installation reports.
This is a compatibility choice for applications that enable desktop features
when no virtualisation is detected.  It is NOT a security boundary and does
not hide a container from software that inspects cgroups or /.dockerenv.
"""
from __future__ import annotations

import os
import sys

KNOWN = [
    "none",
    "kvm",
    "qemu",
    "vmware",
    "microsoft",
    "oracle",
    "xen",
    "bochs",
    "uml",
    "parallels",
    "bhyve",
    "docker",
    "podman",
    "lxc",
    "systemd-nspawn",
    "container-other",
]


def main(argv: list[str]) -> int:
    if "--version" in argv:
        print("systemd 255")
        return 0
    if "--help" in argv or "-h" in argv:
        print("systemd-detect-virt [OPTIONS...]")
        print("  --container   Detect container virtualization")
        print("  --vm          Detect full-machine virtualization")
        print("  --quiet       Suppress output, only return status")
        print("  --list        List known virtualization technologies")
        return 0
    if "--list" in argv:
        print("\n".join(KNOWN))
        return 0

    if "--container" in argv:
        value = os.environ.get("SYSTEMD_DETECT_VIRT_CONTAINER", "none")
    elif "--vm" in argv:
        value = os.environ.get("SYSTEMD_DETECT_VIRT_VM", "none")
    else:
        value = os.environ.get("SYSTEMD_DETECT_VIRT", "none")

    value = value.strip() or "none"
    detected = value != "none"
    if "--quiet" in argv:
        return 0 if detected else 1
    print(value)
    return 0 if detected else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
