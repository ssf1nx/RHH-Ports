"""
Pharos Service — install/uninstall the background update-checker daemon.

Each supported bucket gets its own autostart hook (systemd unit / userland
service script). Plus an ES event script that SIGHUPs the daemon on
game-end, so users see fresh notifications when ES regains the foreground.

MuOS is detected but unsupported for the background daemon: it has no
ES-style game-end hook directory, and patching `/opt/muos/script/mux/
launch.sh` is fragile across MuOS updates. MuOS users run Pharos's UI
directly to check for updates; status_text() reports "Not supported on
this CFW (muos)" for the install screen.

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

import functools
import hashlib
import json
import os
import shutil
import signal
import subprocess
from pathlib import Path

from config import BASE_PATH, INSTALL_DIR

DAEMON_NAME = "pharos-daemon"

# Single source of truth for the "this CFW isn't supported" message —
# used by status_text() and the early-out in install/uninstall so we
# don't drift across multiple wordings.
UNSUPPORTED_MSG = "CFW '{cfw}' not supported"

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
SYSTEMD_UNIT_PATH = Path("/storage/.config/system.d/pharos-daemon.service")
USERLAND_SERVICE_PATH = Path("/userdata/system/services/pharos-daemon")

# ES event-script paths (ROCKNIX + Batocera-family).
SYSTEMD_ES_SCRIPT = Path("/storage/.config/emulationstation/scripts/game-end/pharos-check")
USERLAND_ES_SCRIPT = Path("/userdata/system/configs/emulationstation/scripts/game-end/pharos-check")

DAEMON_PID_FILE = Path(INSTALL_DIR) / "resources" / "daemon.pid"


# ----------------------------------------------------------------------
# CFW detection
# ----------------------------------------------------------------------
# CFW_NAME values (case-insensitive) PortMaster's device_info.txt may
# export. Family-grouped: every member of a tuple shares the same
# install code path (paths + service framework + ES-frontend HTTP notify).
_LIBREELEC_FAMILY = ("rocknix", "amberelec", "jelos", "emuelec", "unofficialos")
_BATOCERA_FAMILY = ("batocera", "knulli", "reglinux")
_KNOWN_UNSUPPORTED = (
    "muos", "arkos", "retrodeck", "trimui", "miyoo", "thera", "retrooz",
)


def _verify_systemd_capable() -> bool:
    """The 'systemd' bucket's install + notify prereqs: systemd CLI, the
    LibreELEC-family /storage user-systemd dir, and a batocera-ES
    scripts dir. Belt-and-braces — env can be wrong (sandbox, dev VM,
    weird fork) so we verify the capability before trusting the label."""
    return (
        shutil.which("systemctl") is not None
        and Path("/storage/.config/system.d").exists()
        and Path("/storage/.config/emulationstation/scripts").exists()
    )


def _verify_userland_capable() -> bool:
    """The 'userland' bucket's install + notify prereqs: Batocera
    settings CLI, /userdata services dir, and batocera-ES scripts dir."""
    return (
        shutil.which("batocera-settings-set") is not None
        and Path("/userdata/system/services").exists()
        and Path("/userdata/system/configs/emulationstation/scripts").exists()
    )


@functools.lru_cache(maxsize=1)
def detect_cfw() -> str:
    """Returns 'systemd' / 'userland' / 'muos' / 'unknown' (or a
    known-but-unsupported lowercase CFW name like 'arkos' / 'retrodeck'
    so the user-facing 'not supported' message shows what we actually
    saw, not just 'unknown').

    Bucket names describe the install mechanism, not a specific CFW —
    'systemd' covers the LibreELEC family (ROCKNIX, AmberELEC, JELOS,
    EmuELEC, UnofficialOS), 'userland' covers the Batocera family
    (Knulli, Batocera, REGLinux). Both buckets share the batocera-ES
    HTTP /notify endpoint and the ES scripts/game-end/ hook.

    Detection order:
      1. PortMaster's $CFW_NAME — set by PortMaster/device_info.txt and
         exported via control.txt for every port launch. Authoritative
         when present (Pharos runs as a port).
      2. Filesystem markers — fallback for the daemon (init-launched, no
         inherited env) and Pharos runs outside PM (diagnostics).
      3. Capability verification — if env or markers point at a supported
         bucket but the install/notify prereqs aren't actually on disk,
         downgrade to 'unknown' so the user sees an accurate
         'not supported' instead of a later opaque install failure.

    Cached: detection is invariant within a process, and we want the
    diagnostic log line to fire exactly once per Pharos run."""
    env_name = (os.environ.get("CFW_NAME") or "").lower()
    bucket: str | None = None

    if env_name in _LIBREELEC_FAMILY:
        bucket = "systemd"
    elif env_name in _BATOCERA_FAMILY:
        bucket = "userland"
    elif env_name in _KNOWN_UNSUPPORTED:
        print(f"[Service] CFW detect: env={env_name!r} (known unsupported)")
        return env_name

    if bucket is None:
        if Path("/run/muos").exists() or Path("/opt/muos").exists():
            print(f"[Service] CFW detect: env={env_name!r} fs=muos")
            return "muos"
        if Path("/userdata/system").exists():
            bucket = "userland"
        elif Path("/storage/.config/emulationstation").exists():
            bucket = "systemd"

    if bucket is None:
        print(f"[Service] CFW detect: env={env_name!r} fs=<no markers> -> unknown")
        return "unknown"

    verifier = _verify_systemd_capable if bucket == "systemd" else _verify_userland_capable
    if not verifier():
        print(
            f"[Service] CFW detect: env={env_name!r} bucket={bucket!r} "
            "but capability check failed; downgrading to 'unknown'"
        )
        return "unknown"

    print(f"[Service] CFW detect: env={env_name!r} bucket={bucket!r} verified")
    return bucket


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
WantedBy=default.target
"""


def _userland_service(daemon_path: Path) -> str:
    return f"""#!/bin/sh
# Pharos update checker daemon — Batocera-style user service.
# Batocera's S99userservices runs this with start/stop arg.
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


def _cleanup_runtime_files() -> None:
    """Remove pid / state / log files left behind by the daemon. The
    daemon's SIGTERM handler normally clears its own pidfile, but we do it
    here too so an `Uninstall` after a wedged or already-dead daemon leaves
    no trace."""
    for f in (
        Path(INSTALL_DIR) / "resources" / "daemon.pid",
        Path(INSTALL_DIR) / "resources" / "daemon.state.json",
        Path(INSTALL_DIR) / "logs" / "daemon.log",
    ):
        try:
            f.unlink(missing_ok=True)
        except OSError:
            pass


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
            print(f"[Service] daemon already at {DAEMON_EXTRACTED_PATH}; skipping extract")
            return True
        if not DAEMON_BUNDLED_PATH.exists():
            print(f"[Service] ERROR: bundled daemon missing at {DAEMON_BUNDLED_PATH}")
            return False
        try:
            shutil.copy2(DAEMON_BUNDLED_PATH, DAEMON_EXTRACTED_PATH)
            DAEMON_EXTRACTED_PATH.chmod(0o755)
            print(f"[Service] extracted daemon: {DAEMON_BUNDLED_PATH} -> {DAEMON_EXTRACTED_PATH}")
            return True
        except OSError as e:
            print(f"[Service] ERROR: extract failed: {e}")
            return False

    @property
    def supported(self) -> bool:
        return self.cfw in ("systemd", "userland")

    @property
    def installed(self) -> bool:
        """Detect by the presence of the per-CFW autostart artefact."""
        if self.cfw == "systemd":
            return SYSTEMD_UNIT_PATH.exists()
        if self.cfw == "userland":
            return USERLAND_SERVICE_PATH.exists()
        return False

    def status_text(self) -> str:
        if not self.supported:
            return UNSUPPORTED_MSG.format(cfw=self._cfw_display_name())
        return "Installed" if self.installed else "Not installed"

    def _unsupported_result(self) -> tuple[bool, str]:
        return False, UNSUPPORTED_MSG.format(cfw=self._cfw_display_name())

    def _cfw_display_name(self) -> str:
        """Friendly CFW name for user-facing strings. Pulls $CFW_NAME from
        PortMaster's exported env (preserves casing — 'AmberELEC', 'muOS',
        'TrimUI'). Falls back to our internal lowercase dispatch key if
        env isn't set (daemon path, Pharos run outside PortMaster)."""
        return os.environ.get("CFW_NAME") or self.cfw

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
        if self.cfw == "systemd":
            _safe_run(["systemctl", "restart", "pharos-daemon.service"])
        elif self.cfw == "userland":
            _safe_run([str(USERLAND_SERVICE_PATH), "stop"])
            _safe_run([str(USERLAND_SERVICE_PATH), "start"])
        return True

    # ------------------------------------------------------------------
    # Install / uninstall — per-CFW dispatch
    # ------------------------------------------------------------------
    def install(self) -> tuple[bool, str]:
        if not self.supported:
            return self._unsupported_result()
        if not self._extract_daemon():
            return False, f"could not extract daemon to {self.daemon_path}"
        try:
            if self.cfw == "systemd":
                return self._install_systemd()
            if self.cfw == "userland":
                return self._install_userland()
        except OSError as e:
            return False, f"install failed: {e}"
        return self._unsupported_result()

    def uninstall(self) -> tuple[bool, str]:
        if not self.supported:
            return self._unsupported_result()
        try:
            if self.cfw == "systemd":
                return self._uninstall_systemd()
            if self.cfw == "userland":
                return self._uninstall_userland()
        except OSError as e:
            return False, f"uninstall failed: {e}"
        return self._unsupported_result()

    # ---- systemd bucket (LibreELEC family) --------------------------
    def _install_systemd(self) -> tuple[bool, str]:
        # Defensive: kill any stale daemon + state files left behind by a
        # previous run (e.g. user updated Pharos manually so the old daemon
        # keeps running and its pidfile blocks the new one from starting).
        rc, msg = _safe_run(["systemctl", "stop", "pharos-daemon.service"])
        print(f"[Service] pre-install stop (rc={rc}) {msg}")
        _cleanup_runtime_files()
        print("[Service] cleaned stale runtime files")

        print(f"[Service] writing systemd unit -> {SYSTEMD_UNIT_PATH}")
        _write_executable(SYSTEMD_UNIT_PATH, _systemd_unit(self.daemon_path))
        rc, msg = _safe_run(["systemctl", "daemon-reload"])
        print(f"[Service] systemctl daemon-reload (rc={rc}) {msg}")
        rc, msg = _safe_run(["systemctl", "enable", "pharos-daemon.service"])
        print(f"[Service] systemctl enable (rc={rc}) {msg}")
        rc, msg = _safe_run(["systemctl", "start", "pharos-daemon.service"])
        print(f"[Service] systemctl start (rc={rc}) {msg}")
        if rc != 0:
            return False, f"systemctl start failed: {msg}"
        print(f"[Service] writing ES event script -> {SYSTEMD_ES_SCRIPT}")
        _write_executable(SYSTEMD_ES_SCRIPT, _es_event_script())
        return True, "Installed (systemd unit enabled + ES hook)"

    def _uninstall_systemd(self) -> tuple[bool, str]:
        rc, msg = _safe_run(["systemctl", "stop", "pharos-daemon.service"])
        print(f"[Service] systemctl stop (rc={rc}) {msg}")
        rc, msg = _safe_run(["systemctl", "disable", "pharos-daemon.service"])
        print(f"[Service] systemctl disable (rc={rc}) {msg}")
        existed = SYSTEMD_UNIT_PATH.exists()
        SYSTEMD_UNIT_PATH.unlink(missing_ok=True)
        print(f"[Service] removed unit file {SYSTEMD_UNIT_PATH} (existed={existed})")
        existed = SYSTEMD_ES_SCRIPT.exists()
        SYSTEMD_ES_SCRIPT.unlink(missing_ok=True)
        print(f"[Service] removed ES script {SYSTEMD_ES_SCRIPT} (existed={existed})")
        _safe_run(["systemctl", "daemon-reload"])
        existed = DAEMON_EXTRACTED_PATH.exists()
        DAEMON_EXTRACTED_PATH.unlink(missing_ok=True)
        print(f"[Service] removed daemon binary {DAEMON_EXTRACTED_PATH} (existed={existed})")
        _cleanup_runtime_files()
        print("[Service] cleaned up runtime files (pid/state/log)")
        return True, "Uninstalled"

    # ---- userland bucket (Batocera-family user-service) -------------
    def _install_userland(self) -> tuple[bool, str]:
        # Defensive: stop any stale daemon + clear pid/state files first.
        if USERLAND_SERVICE_PATH.exists():
            _safe_run([str(USERLAND_SERVICE_PATH), "stop"])
        _kill_pid_file(Path("/var/run/pharos-daemon.pid"))
        _cleanup_runtime_files()
        print("[Service] cleaned stale runtime files")

        _write_executable(USERLAND_SERVICE_PATH, _userland_service(self.daemon_path))
        _safe_run([
            "batocera-settings-set", "system.services.pharos-daemon", "enabled"
        ])
        # Start it now too, so the user doesn't have to reboot.
        _safe_run([str(USERLAND_SERVICE_PATH), "start"])
        _write_executable(USERLAND_ES_SCRIPT, _es_event_script())
        return True, "Installed (Batocera service registered + ES hook)"

    def _uninstall_userland(self) -> tuple[bool, str]:
        if USERLAND_SERVICE_PATH.exists():
            _safe_run([str(USERLAND_SERVICE_PATH), "stop"])
        _safe_run([
            "batocera-settings-set", "system.services.pharos-daemon", "disabled"
        ])
        USERLAND_SERVICE_PATH.unlink(missing_ok=True)
        USERLAND_ES_SCRIPT.unlink(missing_ok=True)
        _kill_pid_file(Path("/var/run/pharos-daemon.pid"))
        DAEMON_EXTRACTED_PATH.unlink(missing_ok=True)
        _cleanup_runtime_files()
        return True, "Uninstalled"

