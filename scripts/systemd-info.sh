#!/bin/bash
set -Eeuo pipefail

clear 2>/dev/null || true
echo "============================================================"
echo " Ubuntu Cloud Desktop - systemd compatibility layer"
echo "============================================================"
echo
echo "--- PID 1 -------------------------------------------------"
ps -p 1 -o pid=,comm=,args= || true
echo
echo "--- systemctl is-system-running ----------------------------"
systemctl is-system-running || true
echo
echo "--- systemctl status --------------------------------------"
systemctl --no-pager status || true
echo
echo "--- systemd-detect-virt -----------------------------------"
systemd-detect-virt || true
echo
echo "--- hostnamectl -------------------------------------------"
hostnamectl || true
echo
echo "--- timedatectl -------------------------------------------"
timedatectl || true
echo
echo "--- journalctl (last 15 lines) ----------------------------"
journalctl -n 15 --no-pager || true
echo
echo "============================================================"
echo " Press Enter to close this window."
read -r _
