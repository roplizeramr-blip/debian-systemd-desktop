#!/bin/bash
# Run inside the running container:
#   docker compose exec desktop /opt/desktop/tests/smoke-test.sh
set -u

PASS=0
FAIL=0
PORT="${NOVNC_PORT:-${PORT:-3000}}"

check() {
    local label="$1"
    shift
    if "$@" >/tmp/compat-check.out 2>&1; then
        echo "PASS  $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL  $label"
        sed 's/^/      /' /tmp/compat-check.out || true
        FAIL=$((FAIL + 1))
    fi
}

check_contains() {
    local label="$1" needle="$2"
    shift 2
    if "$@" >/tmp/compat-check.out 2>&1 && grep -q "$needle" /tmp/compat-check.out; then
        echo "PASS  $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL  $label"
        sed 's/^/      /' /tmp/compat-check.out || true
        FAIL=$((FAIL + 1))
    fi
}

echo "== Ubuntu Cloud Desktop smoke test =="
check "systemctl exists" command -v systemctl
check "systemctl --version" systemctl --version
check "/run/systemd/system exists" test -d /run/systemd/system
check "PID 1 is named systemd" bash -c '[ "$(ps -p 1 -o comm= | tr -d " ")" = "systemd" ]'
check "system is running" bash -c '[ "$(systemctl is-system-running)" = "running" ]'
check "xvnc is active" bash -c '[ "$(systemctl is-active xvnc.service)" = "active" ]'
check "novnc is active" bash -c '[ "$(systemctl is-active novnc.service)" = "active" ]'
check "detect-virt reports none" bash -c '[ "$(systemd-detect-virt)" = "none" ]'
check_contains "hostnamectl reports Ubuntu" "Ubuntu" hostnamectl
check_contains "systemctl list-units includes xvnc" "xvnc.service" systemctl list-units --type=service --no-pager
check "health endpoint" curl -fsS "http://127.0.0.1:${PORT}/healthz"
check_contains "Firefox is installed" "Mozilla Firefox" firefox --version
check "D-Bus manager is introspectable" bash -c 'busctl --system introspect org.freedesktop.systemd1 /org/freedesktop/systemd1 >/dev/null 2>&1'

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
