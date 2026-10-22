# Architecture

## Boot chain

```
Docker CMD
  └─ /usr/local/bin/systemd  (symlink to /usr/bin/supervisord)
       └─ Supervisor PID 1
            ├─ systemd-journald  (journal socket sink)
            ├─ dbus              (system D-Bus daemon)
            ├─ systemd-dbus      (org.freedesktop.systemd1 facade)
            ├─ xvnc              (TigerVNC on :1, loopback:5901)
            ├─ xfce              (XFCE session on DISPLAY=:1)
            └─ novnc             (websockify on 0.0.0.0:3000)
```

Desktop setup (wallpaper, launchers and browser defaults) runs inside the
XFCE program's `dbus-run-session`, not as a separate Supervisor program.  It
must share the session bus with XFCE so `xfconf-query` can reach the running
`xfconfd`.

The entrypoint prepares `/run/systemd/system`, `/run/dbus`,
`/run/user/1000`, a VNC password, `/dev/log` and the machine ID before
`exec`-ing Supervisord.

## Why Supervisor as PID 1?

Supervisor is already a process manager with start/stop/restart semantics,
logging and a control socket.  Running it as PID 1 gives the container a
normal init-like parent, avoids zombie processes, and keeps the image small.
The container command is a symlink named `systemd`, so `/proc/1/comm` matches
the compatibility layer.  The real executable remains Supervisord.

## Unit model

- Unit files live in `/etc/systemd/system` and standard systemd directories.
- Core services are static Supervisor programs.
- Arbitrary services are translated into `/etc/supervisor/conf.d/unit_*.conf`
  when `systemctl start` is called.  `ExecStart=`, `Environment=`, `User=`,
  `WorkingDirectory=` and `Restart=` are supported; `Group=` is reported for
  status/D-Bus compatibility but Supervisor does not change the process group.
- `systemctl enable` creates `<target>.wants/` symlinks and, for dynamic
  units, sets Supervisor `autostart=true`.
- Targets (`graphical.target`, `multi-user.target`) aggregate dependencies.

## systemctl shim

`systemd/systemctl.py`:

1. Parses systemctl-style options.
2. Resolves unit files.
3. Maps units to Supervisor programs.
4. Calls `supervisorctl` over `/run/supervisor.sock`.
5. Formats systemctl-like output and exit codes.

## D-Bus facade

`systemd/systemd_dbus.py` owns `org.freedesktop.systemd1` on the system bus.
It exports:

- `/org/freedesktop/systemd1` → `Manager`
- `/org/freedesktop/systemd1/unit/<escaped>` → `Unit`, `Service`, `Target`
- `/org/freedesktop/systemd1/job/<id>` → `Job`

`GetUnit`, `ListUnits`, `StartUnit`, `StopUnit`, `RestartUnit`,
`GetUnitFileState`, `EnableUnitFiles`, `DisableUnitFiles`, `GetDefaultTarget`
and common properties are implemented.  `JobNew` / `JobRemoved` signals are
emitted around Supervisor operations.

D-Bus activation is configured in
`/usr/share/dbus-1/system-services/org.freedesktop.systemd1.service`; policy
is in `/etc/dbus-1/system.d/org.freedesktop.systemd1.conf`.

## Journal path

`systemd-journald.py` creates:

- `/run/systemd/journal/socket` (datagram)
- `/run/systemd/journal/dev-log` (datagram, also linked from `/dev/log`)
- `/run/systemd/journal/stdout` (stream)

Messages are appended to `/var/log/journal/compat.log`.  `journalctl.py`
reads that file plus `/var/log/supervisor/*.log`.

## Security boundary

The facade is deliberately not an anti-detection product.  It does not alter
cgroups, kernel namespaces, overlayfs, the Docker network or `/proc/1/exe`.
`HIDE_CONTAINER=1` only removes `/.dockerenv`; that is a small compatibility
convenience, not a guarantee.
