#!/bin/bash
# Exercise the dynamic unit path.  Run as root inside the container.
set -u

UNIT="compat-test.service"
UNIT_PATH="/etc/systemd/system/${UNIT}"
PASS=0
FAIL=0

cleanup() {
    systemctl stop "$UNIT" >/dev/null 2>&1 || true
    systemctl disable "$UNIT" >/dev/null 2>&1 || true
    rm -f "$UNIT_PATH"
    systemctl daemon-reload >/dev/null 2>&1 || true
}
trap cleanup EXIT

check() {
    local label="$1"
    shift
    if "$@" >/tmp/systemd-test.out 2>&1; then
        echo "PASS  $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL  $label"
        sed 's/^/      /' /tmp/systemd-test.out || true
        FAIL=$((FAIL + 1))
    fi
}

cat > "$UNIT_PATH" <<'EOF'
[Unit]
Description=Compatibility layer test unit
After=dbus.service

[Service]
Type=simple
ExecStart=/bin/sleep 300
Restart=no

[Install]
WantedBy=multi-user.target
EOF

check "daemon-reload" systemctl daemon-reload
check "start dynamic unit" systemctl start "$UNIT"
check "dynamic unit is active" bash -c "[ \"\$(systemctl is-active $UNIT)\" = active ]"
check "dynamic unit appears in list-units" bash -c "systemctl list-units --type=service --all --no-pager | grep -q $UNIT"
check "dynamic unit is stoppable" systemctl stop "$UNIT"
check "dynamic unit is inactive" bash -c "[ \"\$(systemctl is-active $UNIT)\" = inactive ]"
check "enable dynamic unit" systemctl enable "$UNIT"
check "dynamic unit is enabled" bash -c "[ \"\$(systemctl is-enabled $UNIT)\" = enabled ]"
check "disable dynamic unit" systemctl disable "$UNIT"
check "dynamic unit is disabled" bash -c "[ \"\$(systemctl is-enabled $UNIT)\" = disabled ]"

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
