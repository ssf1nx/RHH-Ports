#!/usr/bin/env python3
"""
pharos-daemon — background update-checker for Pharos.

Event-driven: runs an initial check on startup, then sleeps until SIGHUP
(fired by the ES game-end script the Service installer drops). On wake,
re-checks Pharos's manifest against each repo's docs/ports.json and fires
a single ES notification for any outdated ports. Dedup state is
process-local — a daemon restart yields a fresh notification, which is
the point: ES restarts re-show the toast.

Only the 'systemd' bucket (LibreELEC family — ROCKNIX, AmberELEC, JELOS,
EmuELEC, UnofficialOS) and the 'userland' bucket (Batocera family —
Knulli, Batocera, REGLinux) are supported as daemon hosts. MuOS detection
is preserved for accurate logging but no notification backend is wired up
(MuOS users invoke Pharos directly to check for updates).

Usage (the Pharos Service installer takes care of all this — direct
invocation is for diagnostics only):
  pharos-daemon              # daemon loop
  pharos-daemon --once       # single check + exit
  pharos-daemon --verbose    # echo logs to stderr
"""
from __future__ import annotations

import argparse
import functools
import hashlib
import json
import os
import shutil
import signal
import socket
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Iterable
from urllib.error import HTTPError, URLError

# Minimal CFWs (Knulli) ship Python without CA certs in OpenSSL's default
# search path, so HTTPS requests fail with CERTIFICATE_VERIFY_FAILED. Point
# urllib + ssl at our bundled certifi store before anything tries to fetch.
import certifi
os.environ.setdefault("SSL_CERT_FILE", certifi.where())
os.environ.setdefault("REQUESTS_CA_BUNDLE", certifi.where())

# ----------------------------------------------------------------------
# Paths
# ----------------------------------------------------------------------
INSTALL_DIR = Path(os.path.dirname(os.path.abspath(sys.argv[0])))
SOURCES_PATH = INSTALL_DIR / ".sources"
MANIFEST_PATH = INSTALL_DIR / "resources" / "manifest.json"

PID_FILE = INSTALL_DIR / "resources" / "daemon.pid"
LOG_FILE = INSTALL_DIR / "logs" / "daemon.log"

PID_FILE.parent.mkdir(parents=True, exist_ok=True)
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

# Minimum gap between successive GitHub fetches. Keeps SIGHUP storms
# (back-to-back game-end events on the same session) from hammering the
# API. 5 minutes is generous enough to cover legitimate retries while
# still rate-limiting. Hardcoded — production daemon doesn't need tuning.
MIN_FETCH_INTERVAL_S = 300

RETRY_BACKOFF_INITIAL = 5
RETRY_BACKOFF_MAX = 60
GITHUB_HTTP_TIMEOUT = 10

# ----------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------
_verbose = False

def log(level: str, msg: str) -> None:
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [{level}] {msg}\n"
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line)
    except OSError:
        pass
    if _verbose or level in ("ERROR", "WARN"):
        sys.stderr.write(line)

# ----------------------------------------------------------------------
# CFW detection + notification backends
# ----------------------------------------------------------------------
# CFW_NAME values (case-insensitive) PortMaster's device_info.txt may
# export. Mirrors the family grouping used in service.py so dispatch is
# consistent if/when env *is* set (manual --once invocation outside init).
_LIBREELEC_FAMILY = ("rocknix", "amberelec", "jelos", "emuelec", "unofficialos")
_BATOCERA_FAMILY = ("batocera", "knulli", "reglinux")
_KNOWN_UNSUPPORTED = (
    "muos", "arkos", "retrodeck", "trimui", "miyoo", "thera", "retrooz",
)


def _verify_systemd_capable() -> bool:
    """The 'systemd' bucket's notify prereqs: systemd CLI + LibreELEC
    /storage layout + batocera-ES scripts dir. Mirrors service.py."""
    return (
        shutil.which("systemctl") is not None
        and Path("/storage/.config/system.d").exists()
        and Path("/storage/.config/emulationstation/scripts").exists()
    )


def _verify_userland_capable() -> bool:
    """The 'userland' bucket's notify prereqs."""
    return (
        shutil.which("batocera-settings-set") is not None
        and Path("/userdata/system/services").exists()
        and Path("/userdata/system/configs/emulationstation/scripts").exists()
    )


@functools.lru_cache(maxsize=1)
def detect_cfw() -> str:
    """Returns 'systemd' / 'userland' / 'muos' / 'unknown' (or a
    known-but-unsupported lowercase name like 'arkos'). Mirrors
    service.py.detect_cfw — duplicated rather than shared because the
    daemon ships as its own PyInstaller binary.

    Bucket names describe install/notify mechanism, not specific CFWs:
    'systemd' = LibreELEC family, 'userland' = Batocera family.

    The env-driven branch is dead code on the normal init-launched path
    (no $CFW_NAME inherited) but kept symmetric with service.py so a
    `pharos-daemon --once` run from inside PortMaster's env still hits
    the same logic. Capability verification gates the supported buckets
    so a misidentified host downgrades to 'unknown' rather than
    silently failing on the notify backend."""
    env_name = (os.environ.get("CFW_NAME") or "").lower()
    bucket: str | None = None

    if env_name in _LIBREELEC_FAMILY:
        bucket = "systemd"
    elif env_name in _BATOCERA_FAMILY:
        bucket = "userland"
    elif env_name in _KNOWN_UNSUPPORTED:
        log("INFO", f"CFW detect: env={env_name!r} (known unsupported)")
        return env_name

    if bucket is None:
        if Path("/run/muos").exists() or Path("/opt/muos").exists():
            log("INFO", f"CFW detect: env={env_name!r} fs=muos")
            return "muos"
        if Path("/userdata/system").exists():
            bucket = "userland"
        elif Path("/storage/.config/emulationstation").exists():
            bucket = "systemd"

    if bucket is None:
        log("WARN", f"CFW detect: env={env_name!r} fs=<no markers> -> unknown")
        return "unknown"

    verifier = _verify_systemd_capable if bucket == "systemd" else _verify_userland_capable
    if not verifier():
        log(
            "WARN",
            f"CFW detect: env={env_name!r} bucket={bucket!r} but capability "
            "check failed; downgrading to 'unknown'",
        )
        return "unknown"

    log("INFO", f"CFW detect: env={env_name!r} bucket={bucket!r} verified")
    return bucket

def notify_es_http(message: str) -> bool:
    """Both supported buckets share the batocera-ES HTTP /notify endpoint."""
    try:
        req = urllib.request.Request(
            "http://127.0.0.1:1234/notify",
            data=message.encode("utf-8"),
            headers={"Content-Type": "text/plain"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=3):
            return True
    except (HTTPError, URLError, socket.timeout, OSError) as e:
        log("WARN", f"notify_es_http failed: {e}")
        return False

def notify(cfw: str, message: str) -> bool:
    if cfw in ("systemd", "userland"):
        return notify_es_http(message)
    log("WARN", f"unsupported CFW '{cfw}'; would have sent: {message}")
    return False

# ----------------------------------------------------------------------
# Update check
# ----------------------------------------------------------------------
# Counts transport-level failures (URLError, socket.timeout, OSError) within
# a single run_check pass. HTTPError is a real response and isn't counted —
# it means the network worked but the server said no. Reset by run_check at
# entry, read at exit so the caller can distinguish "no updates because
# nothing changed" from "no updates because the network was down".
_network_errors_this_pass = 0


def _http_get(url: str, timeout: int = GITHUB_HTTP_TIMEOUT) -> bytes | None:
    """Fetch a URL. 200 -> bytes. 404 -> silent None (callers handle "not found"
    semantically). Other HTTP errors -> WARN + None. Transport failures ->
    WARN + None + bump _network_errors_this_pass so daemon_loop knows to
    schedule a retry rather than waiting for SIGHUP."""
    global _network_errors_this_pass
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "PharosDaemon/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except HTTPError as e:
        if e.code != 404:
            log("WARN", f"http GET {url} -> HTTP {e.code}")
        return None
    except (URLError, socket.timeout, OSError) as e:
        _network_errors_this_pass += 1
        log("WARN", f"http GET {url} failed: {e}")
        return None

def load_local_manifest() -> tuple[
    dict[str, str], dict[str, str], dict[str, str], set[str]
]:
    """Returns ({name: md5}, {name: title}, {name: repo}, {muted_names}) for
    ports tracked by Pharos. Names are extensionless. `repo` is empty for
    legacy entries; `muted` defaults to False for entries without the field."""
    if not MANIFEST_PATH.exists():
        log("INFO", f"manifest not found at {MANIFEST_PATH}")
        return {}, {}, {}, set()
    try:
        data = json.loads(MANIFEST_PATH.read_text("utf-8"))
        md5s: dict[str, str] = {}
        titles: dict[str, str] = {}
        repos: dict[str, str] = {}
        muted: set[str] = set()
        for entry in data.get("ports", []) + data.get("bottles", []):
            name = entry.get("name")
            md5 = entry.get("md5")
            if not (name and md5):
                log("INFO", f"manifest entry skipped (missing name/md5): {entry!r}")
                continue
            md5s[name] = md5
            titles[name] = entry.get("title") or name
            repos[name] = entry.get("repo") or ""
            muted_field = entry.get("muted")
            log(
                "INFO",
                f"manifest: name={name!r} md5={md5[:8]} muted={muted_field!r}",
            )
            if muted_field:
                muted.add(name)
        log(
            "INFO",
            f"manifest summary: {len(md5s)} tracked, {len(muted)} muted -> {sorted(muted)}",
        )
        return md5s, titles, repos, muted
    except (OSError, json.JSONDecodeError) as e:
        log("WARN", f"manifest parse failed: {e}")
        return {}, {}, {}, set()

def parse_sources() -> list[tuple[str, str]]:
    """Returns [(owner, repo)] from .sources (one URL per line)."""
    if not SOURCES_PATH.exists():
        log("WARN", f".sources not found at {SOURCES_PATH}")
        return []
    out: list[tuple[str, str]] = []
    for line in SOURCES_PATH.read_text("utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path = urllib.parse.urlparse(line).path.lstrip("/")
        if path.endswith(".git"):
            path = path[:-4]
        if "/" in path:
            owner, name = path.split("/", 1)
            out.append((owner, name))
    return out

def fetch_remote_md5s(owner: str, repo: str) -> tuple[dict[str, str], dict[str, str]]:
    """Returns ({name: md5}, {name: title}) from a repo's docs/ports.json.
    Names stripped of .zip to match the local manifest convention. Wine bottle
    repos (winecask.json) are out of scope: Pharos handles those itself."""
    for branch in ("main", "master"):
        for path in ("docs/ports.json", "ports.json"):
            url = f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}"
            raw = _http_get(url)
            if raw is None:
                continue
            try:
                data = json.loads(raw)
                ports = data.get("ports", data) if isinstance(data, dict) else data
                md5s: dict[str, str] = {}
                titles: dict[str, str] = {}
                for p in ports:
                    raw_name = p.get("name") or ""
                    md5 = (p.get("source", {}) or {}).get("md5")
                    if not (raw_name and md5):
                        continue
                    name = os.path.splitext(raw_name)[0]
                    md5s[name] = md5
                    titles[name] = (p.get("attr", {}) or {}).get("title") or name
                return md5s, titles
            except json.JSONDecodeError:
                continue
    log("INFO", f"no ports.json on {owner}/{repo}; skipping")
    return {}, {}

def find_outdated(
    local: dict[str, str], local_repos: dict[str, str]
) -> tuple[list[str], dict[str, str]]:
    """Returns (sorted outdated names, remote-title fallback dict).

    Per-port:
      - If local_repos[name] is set ("owner/name"): only that repo's
        ports.json can mark the port outdated. Authoritative.
      - If empty (legacy entry): match-any across every repo in .sources.
        Outdated only when no repo currently publishes the local md5.
    """
    repos_in_sources = parse_sources()
    fetched: dict[tuple[str, str], tuple[dict[str, str], dict[str, str]]] = {}

    def remote_for(or_: tuple[str, str]) -> tuple[dict[str, str], dict[str, str]]:
        if or_ not in fetched:
            fetched[or_] = fetch_remote_md5s(*or_)
        return fetched[or_]

    outdated: list[str] = []
    remote_titles: dict[str, str] = {}

    for name, local_md5 in local.items():
        recorded = local_repos.get(name) or ""
        if recorded and "/" in recorded:
            owner, repo = recorded.split("/", 1)
            md5s, titles = remote_for((owner, repo))
            remote_md5 = md5s.get(name)
            if remote_md5 and remote_md5 != local_md5:
                outdated.append(name)
            if titles.get(name):
                remote_titles.setdefault(name, titles[name])
        else:
            seen: set[str] = set()
            for or_ in repos_in_sources:
                md5s, titles = remote_for(or_)
                if name in md5s:
                    seen.add(md5s[name])
                    if titles.get(name):
                        remote_titles.setdefault(name, titles[name])
            if seen and local_md5 not in seen:
                outdated.append(name)

    return sorted(outdated), remote_titles

def format_message(outdated: Iterable[str], titles: dict[str, str]) -> str:
    items = list(outdated)
    if len(items) == 1:
        return f"[PHAROS] Update available for {titles.get(items[0], items[0])}"
    return f"[PHAROS] {len(items)} updates available"

# ----------------------------------------------------------------------
# Notify-state dedup (process-local; daemon restart wipes it)
# ----------------------------------------------------------------------
def _outdated_hash(items: Iterable[str]) -> str:
    return hashlib.sha256(",".join(sorted(items)).encode("utf-8")).hexdigest()

_state_cache: dict = {}

# ----------------------------------------------------------------------
# Main check
# ----------------------------------------------------------------------
def run_check() -> tuple[bool, bool]:
    """One check + notify pass. Returns (settled, network_failed).

      settled        — True on settled state (notify ok or nothing to do);
                       False on notify failure (caller may retry).
      network_failed — True if at least one HTTP fetch hit a transport
                       error (URLError/timeout/OSError). Independent of
                       settled — caller schedules a retry alarm so updates
                       aren't missed when the boot-time network was down.

    The two flags are independent: notify failure is a settled-state issue
    (server returned, our notify backend choked); network failure is a
    fetch-state issue (couldn't reach the server)."""
    global _network_errors_this_pass
    _network_errors_this_pass = 0

    local_md5s, local_titles, local_repos, muted = load_local_manifest()
    if not local_md5s:
        log("INFO", "manifest empty; nothing tracked")
        return True, False

    # Strip muted ports up front so they're invisible to the rest of the
    # check pipeline — including dedup (so unmuting later genuinely re-fires).
    if muted:
        log("INFO", f"{len(muted)} port(s) muted: {sorted(muted)}")
        local_md5s = {n: m for n, m in local_md5s.items() if n not in muted}
        if not local_md5s:
            log("INFO", "all tracked ports muted")
            return True, False

    outdated, remote_titles = find_outdated(local_md5s, local_repos)
    network_failed = _network_errors_this_pass > 0
    if not outdated:
        log("INFO", "no updates" + (" (with network failures)" if network_failed else ""))
        return True, network_failed

    h = _outdated_hash(outdated)
    if _state_cache.get("last_outdated_hash") == h:
        log("INFO", f"{len(outdated)} outdated but state unchanged; skipping notify")
        return True, network_failed

    titles = {**remote_titles, **local_titles}
    cfw = detect_cfw()
    msg = format_message(outdated, titles)
    log("INFO", f"notifying ({cfw}): {msg}")

    backoff = RETRY_BACKOFF_INITIAL
    for attempt in range(1, 7):
        if notify(cfw, msg):
            _state_cache["last_outdated_hash"] = h
            return True, network_failed
        time.sleep(backoff)
        backoff = min(backoff * 2, RETRY_BACKOFF_MAX)
        log("INFO", f"notify retry attempt {attempt}")
    log("ERROR", "all notify retries exhausted")
    return False, network_failed

# ----------------------------------------------------------------------
# Daemon loop + signals
# ----------------------------------------------------------------------
_woken = False
_pending = False   # SIGHUP arrived inside rate-limit window; SIGALRM scheduled for window-end
_retrying = False  # last check hit network errors; SIGALRM scheduled for ~60s retry

# Network-retry interval. Shorter than MIN_FETCH_INTERVAL_S because the
# whole point is to recover quickly from a boot-time network race rather
# than wait the full rate-limit window.
NETWORK_RETRY_S = 60


def _on_wake(_signum, _frame) -> None:
    """Shared handler for SIGHUP and SIGALRM — both just wake daemon_loop;
    the loop body decides whether to fetch, defer, or absorb based on
    _pending / _retrying and the rate-limit window."""
    global _woken
    _woken = True


def _on_sigterm(_signum, _frame) -> None:
    log("INFO", "SIGTERM — shutting down")
    sys.exit(0)


def _is_our_daemon(pid: int) -> bool:
    """Best-effort cross-check that /proc/<pid> is actually a Pharos daemon
    rather than an unrelated process the kernel happened to assign the same
    PID after our previous instance died (rare but real on long-running
    systems with intense PID churn). Compares /proc/<pid>/comm against
    /proc/self/comm so we cover renamed binaries and PyInstaller temp
    prefixes without hardcoding a name. If /proc isn't usable on this CFW,
    returns True (preserves the conservative existing behavior of refusing
    to start over a live PID)."""
    comm_file = Path(f"/proc/{pid}/comm")
    if not comm_file.exists():
        return True
    try:
        their_comm = comm_file.read_text().strip()
    except OSError:
        return True
    try:
        our_comm = Path("/proc/self/comm").read_text().strip()
    except OSError:
        # /proc/self should always work if /proc/<pid>/comm did, but if
        # somehow it doesn't, fall back to the literal binary name.
        our_comm = "pharos-daemon"
    return their_comm == our_comm


def write_pidfile() -> None:
    if PID_FILE.exists():
        try:
            old = int(PID_FILE.read_text().strip())
            os.kill(old, 0)
            # Process exists. Cross-check it's actually ours before refusing
            # to start — kernel PID reuse can otherwise lock us out forever.
            if _is_our_daemon(old):
                log("ERROR", f"another instance running (pid {old}); exiting")
                sys.exit(1)
            log("INFO", f"pidfile points at pid {old} but /proc shows it's not our daemon; treating as stale")
        except (OSError, ValueError):
            pass  # process gone or pidfile garbage; take over
    PID_FILE.write_text(str(os.getpid()))


def remove_pidfile() -> None:
    try:
        PID_FILE.unlink()
    except OSError:
        pass


def daemon_loop() -> None:
    """Initial check on startup, then idle until SIGHUP. Each wake re-runs
    the check pass, gated by MIN_FETCH_INTERVAL_S to keep SIGHUP storms
    from hammering GitHub. Two deferral mechanisms keep events from being
    silently dropped:

      _pending  — SIGHUP arrived while rate-limited. Schedule SIGALRM at
                  window-end so the deferred check still fires.
      _retrying — last check hit transport errors. Schedule SIGALRM in
                  NETWORK_RETRY_S so a boot-time network race recovers
                  without waiting for the user to play a game. last_fetch
                  is left stale so the rate limit doesn't block the retry.

    Wake signals (SIGHUP, SIGALRM) are blocked outside the wait so that
    sigsuspend(empty_mask) atomically unblocks-and-waits — the previous
    pause() pattern had a race window where a signal could fire after the
    _woken check but before pause(), getting consumed by the handler while
    pause blocked indefinitely waiting for a successor.

    SIGTERM / Ctrl+C exit cleanly via _on_sigterm (left unblocked so they
    always interrupt promptly)."""
    global _woken, _pending, _retrying
    write_pidfile()
    try:
        signal.signal(signal.SIGHUP, _on_wake)
        signal.signal(signal.SIGALRM, _on_wake)
        signal.signal(signal.SIGTERM, _on_sigterm)
        signal.signal(signal.SIGINT, _on_sigterm)

        # Block wake signals so sigsuspend below is the atomic unblock+wait.
        # SIGTERM/SIGINT stay unblocked so they always interrupt promptly.
        wake_signals = {signal.SIGHUP, signal.SIGALRM}
        signal.pthread_sigmask(signal.SIG_BLOCK, wake_signals)

        # Initial check: covers boot-time notification once ES is up.
        # last_fetch left at 0.0 so the first post-boot SIGHUP isn't
        # rate-limited against the boot check — that SIGHUP is the user's
        # first chance to retry if the boot check ran before network was up.
        last_fetch = 0.0
        _, network_failed = run_check()
        if network_failed:
            log("INFO", f"boot check hit network errors; scheduling retry in {NETWORK_RETRY_S}s")
            signal.alarm(NETWORK_RETRY_S)
            _retrying = True

        empty_mask: set[int] = set()
        while True:
            if not _woken:
                # Atomic unblock + wait. When a signal arrives, the handler
                # runs while signals are unblocked, then sigsuspend returns
                # and the original (blocked) mask is restored — so any
                # further wake signals queue cleanly until the next sigsuspend.
                signal.sigsuspend(empty_mask)
            _woken = False

            now = time.time()
            since = now - last_fetch
            if since < MIN_FETCH_INTERVAL_S:
                remaining = MIN_FETCH_INTERVAL_S - since
                if not _pending:
                    _pending = True
                    # +1s slack so the alarm fires just past the window edge.
                    signal.alarm(int(remaining) + 1)
                    log("INFO", f"woken; rate-limited ({int(remaining)}s remaining); deferred")
                else:
                    log("INFO", f"woken; rate-limited ({int(remaining)}s remaining); already deferred")
                continue

            if _pending:
                log("INFO", "woken (deferred check after rate-limit window)")
            elif _retrying:
                log("INFO", "woken (network-failure retry)")
            else:
                log("INFO", "woken (SIGHUP)")
            _pending = False
            _retrying = False
            signal.alarm(0)

            _, network_failed = run_check()
            if network_failed:
                log("INFO", f"network failure during check; scheduling retry in {NETWORK_RETRY_S}s")
                signal.alarm(NETWORK_RETRY_S)
                _retrying = True
            else:
                last_fetch = time.time()
    finally:
        remove_pidfile()

# ----------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------
def main() -> int:
    global _verbose
    p = argparse.ArgumentParser(description="Pharos update-check daemon.")
    p.add_argument("--once", action="store_true", help="run one check and exit")
    p.add_argument("--verbose", action="store_true", help="echo logs to stderr")
    args = p.parse_args()
    _verbose = args.verbose

    if args.once:
        log("INFO", f"pharos-daemon --once (pid {os.getpid()})")
        _, network_failed = run_check()
        if network_failed:
            log("WARN", "--once detected network failures; daemon mode would schedule a retry")
        return 0

    # Daemon mode: rotate the log on each start so it doesn't grow unbounded
    # across reboots. --once invocations are append-only so diagnostic runs
    # don't clobber the running daemon's history.
    try:
        LOG_FILE.write_text("")
    except OSError:
        pass
    log("INFO", f"pharos-daemon start (pid {os.getpid()}, install_dir {INSTALL_DIR})")

    try:
        daemon_loop()
    except KeyboardInterrupt:
        log("INFO", "interrupted; shutting down")
    return 0

if __name__ == "__main__":
    sys.exit(main())
