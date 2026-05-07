"""
Pharos Service — install/uninstall the background update-checker daemon.

Each CFW gets its own autostart hook (systemd unit / Batocera service /
init.d script). Plus an ES event script that SIGHUPs the daemon on
game-end, so users see fresh notifications when ES regains the foreground.

The daemon ships as its own PyInstaller --onefile binary, embedded inside
the Pharos binary via --add-binary. At runtime the bundled daemon lives in
BASE_PATH (sys._MEIPASS); install() copies it out to INSTALL_DIR as a
persistent executable, uninstall() removes it. The port zip therefore
ships only the Pharos binary — no loose script files anywhere.

refresh_if_stale() is called once on Pharos startup; if the bundled daemon
hash differs from the on-disk extracted copy (which happens after a Pharos
self-update bringing new daemon code), it replaces the file and restarts
the per-CFW service so the new code takes over without user intervention.
"""
from __future__ import annotations

import hashlib
import os
import shutil
import signal
import subprocess
from pathlib import Path

from paths import BASE_PATH, INSTALL_DIR

DAEMON_NAME = "pharos-daemon"

# Bundled binary (read-only, inside _MEIPASS) and on-disk location after install.
DAEMON_BUNDLED_PATH = Path(BASE_PATH) / DAEMON_NAME
DAEMON_EXTRACTED_PATH = Path(INSTALL_DIR) / DAEMON_NAME

# Per-port mute lives on each manifest entry as a "muted" boolean. The
# daemon reads it from the same manifest the Pharos UI mutates here.
MANIFEST_PATH = Path(INSTALL_DIR) / "resources" / "manifest.json"


def toggle_muted_port(name: str) -> bool | None:
    """Flip the "muted" flag on the manifest entry matching `name`. Returns
    the new state (True if now muted), or None if no matching entry exists.
    Atomic write via tmp + rename so a partial save can't corrupt manifest."""
    import json
    if not MANIFEST_PATH.exists():
        return None
    try:
        data = json.loads(MANIFEST_PATH.read_text("utf-8"))
    except (OSError, json.JSONDecodeError):
        return None

    new_state: bool | None = None
    for key in ("ports", "bottles"):
        for entry in data.get(key, []) or []:
            if entry.get("name") == name:
                new_state = not bool(entry.get("muted"))
                entry["muted"] = new_state
                break
        if new_state is not None:
            break

    if new_state is None:
        return None

    tmp = MANIFEST_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    os.replace(tmp, MANIFEST_PATH)
    return new_state

# Per-CFW autostart artefact paths.
ROCKNIX_UNIT_PATH = Path("/storage/.config/system.d/pharos-daemon.service")
KNULLI_SERVICE_PATH = Path("/userdata/system/services/pharos-daemon")
MUOS_INIT_PATH = Path("/opt/muos/script/init/S95pharos.sh")

# ES event-script paths (ROCKNIX + Knulli).
ROCKNIX_ES_SCRIPT = Path("/storage/.config/emulationstation/scripts/game-end/pharos-check")
KNULLI_ES_SCRIPT = Path("/userdata/system/configs/emulationstation/scripts/game-end/pharos-check")

DAEMON_PID_FILE = Path(INSTALL_DIR) / "resources" / "daemon.pid"


# ----------------------------------------------------------------------
# CFW detection
# ----------------------------------------------------------------------
def detect_cfw() -> str:
    """Returns 'rocknix' / 'knulli' / 'muos' / 'unknown'. Filesystem markers,
    not env vars (init.d won't inherit PortMaster's env)."""
    if Path("/run/muos").exists() or Path("/opt/muos").exists():
        return "muos"
    if Path("/userdata/system").exists():
        return "knulli"
    if Path("/storage/.config/emulationstation").exists():
        return "rocknix"
    return "unknown"


# ----------------------------------------------------------------------
# Templates
# ----------------------------------------------------------------------
def _systemd_unit(daemon_path: Path) -> str:
    return f"""[Unit]
Description=Pharos update checker daemon
After=emustation.service
Wants=network-online.target

[Service]
Type=simple
ExecStart={daemon_path}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=rocknix.target
"""


def _knulli_service(daemon_path: Path) -> str:
    return f"""#!/bin/sh
# Pharos update checker daemon — Batocera-style user service.
# Knulli's S99userservices runs this with start/stop arg.
PIDFILE=/var/run/pharos-daemon.pid

case "$1" in
    start)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            exit 0
        fi
        {daemon_path} >/var/log/pharos-daemon.log 2>&1 &
        echo $! > "$PIDFILE"
        ;;
    stop)
        [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
        ;;
    *)
        echo "usage: $0 start|stop" >&2
        exit 1
        ;;
esac
"""


def _muos_init(daemon_path: Path) -> str:
    return f"""#!/bin/sh
# Pharos update checker daemon — MuOS init.d slot.
# Started as part of MuOS boot, re-started on subsequent boots.
PIDFILE=/run/pharos-daemon.pid

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi
{daemon_path} >/var/log/pharos-daemon.log 2>&1 &
echo $! > "$PIDFILE"
"""


def _es_event_script() -> str:
    pid_file = DAEMON_PID_FILE
    return f"""#!/bin/sh
# Pharos: nudge the daemon to re-check whenever ES regains the foreground.
PID_FILE={pid_file}
[ -f "$PID_FILE" ] && kill -HUP "$(cat "$PID_FILE")" 2>/dev/null
exit 0
"""


# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------
def _write_executable(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def _safe_run(cmd: list[str]) -> tuple[int, str]:
    try:
        out = subprocess.run(
            cmd, capture_output=True, text=True, timeout=15, check=False
        )
        return out.returncode, (out.stdout + out.stderr).strip()
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return 1, str(e)


def _kill_pid_file(pid_file: Path) -> None:
    if not pid_file.exists():
        return
    try:
        pid = int(pid_file.read_text().strip())
        os.kill(pid, signal.SIGTERM)
    except (OSError, ValueError):
        pass
    try:
        pid_file.unlink()
    except OSError:
        pass


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(64 * 1024), b""):
                h.update(chunk)
    except OSError:
        return ""
    return h.hexdigest()


# ----------------------------------------------------------------------
# Service class
# ----------------------------------------------------------------------
class Service:
    def __init__(self) -> None:
        self.cfw = detect_cfw()
        # Persistent location after extraction. Survives Pharos exit /
        # _MEIPASS cleanup / reboots — that's the whole point.
        self.daemon_path = DAEMON_EXTRACTED_PATH

    def _extract_daemon(self) -> bool:
        """Copy the bundled daemon out of _MEIPASS to a persistent location.
        Idempotent: if the file is already in place, leave it. Returns True
        on success (or if already present)."""
        if DAEMON_EXTRACTED_PATH.exists():
            return True
        if not DAEMON_BUNDLED_PATH.exists():
            return False
        try:
            shutil.copy2(DAEMON_BUNDLED_PATH, DAEMON_EXTRACTED_PATH)
            DAEMON_EXTRACTED_PATH.chmod(0o755)
            return True
        except OSError:
            return False

    @property
    def supported(self) -> bool:
        return self.cfw in ("rocknix", "knulli", "muos")

    @property
    def installed(self) -> bool:
        """Detect by the presence of the per-CFW autostart artefact."""
        if self.cfw == "rocknix":
            return ROCKNIX_UNIT_PATH.exists()
        if self.cfw == "knulli":
            return KNULLI_SERVICE_PATH.exists()
        if self.cfw == "muos":
            return MUOS_INIT_PATH.exists()
        return False

    def status_text(self) -> str:
        if not self.supported:
            return f"Not supported on this CFW ({self.cfw})"
        return "Installed" if self.installed else "Not installed"

    # ------------------------------------------------------------------
    # Auto-refresh on Pharos update
    # ------------------------------------------------------------------
    def refresh_if_stale(self) -> bool:
        """If the service is installed and the bundled daemon binary differs
        from the extracted on-disk copy, replace it and restart the per-CFW
        service. Returns True if a refresh happened. Called once on Pharos
        startup so a self-update of Pharos transparently brings the daemon
        with it."""
        if not self.installed:
            return False
        if not DAEMON_BUNDLED_PATH.exists() or not DAEMON_EXTRACTED_PATH.exists():
            return False
        if _hash_file(DAEMON_BUNDLED_PATH) == _hash_file(DAEMON_EXTRACTED_PATH):
            return False

        try:
            shutil.copy2(DAEMON_BUNDLED_PATH, DAEMON_EXTRACTED_PATH)
            DAEMON_EXTRACTED_PATH.chmod(0o755)
        except OSError:
            return False

        # Restart the per-CFW service so the new code is what's actually running.
        if self.cfw == "rocknix":
            _safe_run(["systemctl", "restart", "pharos-daemon.service"])
        elif self.cfw == "knulli":
            _safe_run([str(KNULLI_SERVICE_PATH), "stop"])
            _safe_run([str(KNULLI_SERVICE_PATH), "start"])
        elif self.cfw == "muos":
            _kill_pid_file(Path("/run/pharos-daemon.pid"))
            _safe_run([str(MUOS_INIT_PATH)])
        return True

    # ------------------------------------------------------------------
    # Install / uninstall — per-CFW dispatch
    # ------------------------------------------------------------------
    def install(self) -> tuple[bool, str]:
        if not self.supported:
            return False, f"CFW '{self.cfw}' not supported"
        if not self._extract_daemon():
            return False, f"could not extract daemon to {self.daemon_path}"
        try:
            if self.cfw == "rocknix":
                return self._install_rocknix()
            if self.cfw == "knulli":
                return self._install_knulli()
            if self.cfw == "muos":
                return self._install_muos()
        except OSError as e:
            return False, f"install failed: {e}"
        return False, "unreachable"

    def uninstall(self) -> tuple[bool, str]:
        try:
            if self.cfw == "rocknix":
                return self._uninstall_rocknix()
            if self.cfw == "knulli":
                return self._uninstall_knulli()
            if self.cfw == "muos":
                return self._uninstall_muos()
        except OSError as e:
            return False, f"uninstall failed: {e}"
        return False, f"CFW '{self.cfw}' not supported"

    # ---- ROCKNIX (systemd) ------------------------------------------
    def _install_rocknix(self) -> tuple[bool, str]:
        _write_executable(ROCKNIX_UNIT_PATH, _systemd_unit(self.daemon_path))
        # systemd in user-config dir requires daemon-reload then enable+start.
        _safe_run(["systemctl", "daemon-reload"])
        _safe_run(["systemctl", "enable", "pharos-daemon.service"])
        rc, msg = _safe_run(["systemctl", "start", "pharos-daemon.service"])
        if rc != 0:
            return False, f"systemctl start failed: {msg}"
        _write_executable(ROCKNIX_ES_SCRIPT, _es_event_script())
        return True, "Installed (systemd unit enabled + ES hook)"

    def _uninstall_rocknix(self) -> tuple[bool, str]:
        _safe_run(["systemctl", "stop", "pharos-daemon.service"])
        _safe_run(["systemctl", "disable", "pharos-daemon.service"])
        ROCKNIX_UNIT_PATH.unlink(missing_ok=True)
        ROCKNIX_ES_SCRIPT.unlink(missing_ok=True)
        _safe_run(["systemctl", "daemon-reload"])
        DAEMON_EXTRACTED_PATH.unlink(missing_ok=True)
        return True, "Uninstalled"

    # ---- Knulli (Batocera user-service) ------------------------------
    def _install_knulli(self) -> tuple[bool, str]:
        _write_executable(KNULLI_SERVICE_PATH, _knulli_service(self.daemon_path))
        rc, _ = _safe_run([
            "batocera-settings-set", "system.services.pharos-daemon", "enabled"
        ])
        # Start it now too, so the user doesn't have to reboot.
        _safe_run([str(KNULLI_SERVICE_PATH), "start"])
        _write_executable(KNULLI_ES_SCRIPT, _es_event_script())
        return True, "Installed (Batocera service registered + ES hook)"

    def _uninstall_knulli(self) -> tuple[bool, str]:
        if KNULLI_SERVICE_PATH.exists():
            _safe_run([str(KNULLI_SERVICE_PATH), "stop"])
        _safe_run([
            "batocera-settings-set", "system.services.pharos-daemon", "disabled"
        ])
        KNULLI_SERVICE_PATH.unlink(missing_ok=True)
        KNULLI_ES_SCRIPT.unlink(missing_ok=True)
        _kill_pid_file(Path("/var/run/pharos-daemon.pid"))
        return True, "Uninstalled"

    # ---- MuOS (init.d) -----------------------------------------------
    def _install_muos(self) -> tuple[bool, str]:
        _write_executable(MUOS_INIT_PATH, _muos_init(self.daemon_path))
        # Run it now so the user gets a daemon without a reboot.
        _safe_run([str(MUOS_INIT_PATH)])
        return True, "Installed (init.d slot S95pharos.sh registered)"

    def _uninstall_muos(self) -> tuple[bool, str]:
        _kill_pid_file(Path("/run/pharos-daemon.pid"))
        _kill_pid_file(DAEMON_PID_FILE)
        MUOS_INIT_PATH.unlink(missing_ok=True)
        return True, "Uninstalled"
