#!/usr/bin/env python3
"""
Pharos/update.py
Self-update mechanism. Adapted from rommapp/muos-app's RomM/update.py.

Flow:
  1. check() compares the bundled __version__ against the same file fetched
     from PHAROS_REPO@main, and looks up the download URL from docs/ports.json.
  2. download() streams the new zip into DATA_DIR/.pending_update.zip with a
     progress UI driven by Pharos's existing draw_loader/draw_log primitives.
  3. main.py::apply_pending_update() picks up the zip on next launch and
     extracts it over the install dir before any other imports.
"""
import json
import os
import re
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import sdl2

import __version__
from paths import DATA_DIR

# ----------------------------------------------------------------------
# Where Pharos publishes from. Hardcoded because the upgrade source is
# inherent to the tool, not a user choice (unlike .sources for ports).
# ----------------------------------------------------------------------
PHAROS_REPO = "JeodC/RHH-Ports"
PHAROS_VERSION_RAW = (
    f"https://raw.githubusercontent.com/{PHAROS_REPO}/main/"
    "buildtools/pharos/app/__version__.py"
)
PHAROS_PORTS_JSON_RAW = (
    f"https://raw.githubusercontent.com/{PHAROS_REPO}/main/docs/ports.json"
)
PHAROS_PORT_NAME = "pharos.zip"  # matches port.json "name"

PENDING_ZIP = os.path.join(DATA_DIR, ".pending_update.zip")
VERSION_RE = re.compile(r"version\s*=\s*['\"]([^'\"]+)['\"]")


def _http_get(url: str, timeout: int = 5) -> bytes | None:
    try:
        req = Request(url, headers={"User-Agent": "Pharos/Updater"})
        with urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except (HTTPError, URLError, TimeoutError) as e:
        print(f"[Update] {url} failed: {e}")
        return None


def _parse_version(text: str) -> str | None:
    m = VERSION_RE.search(text)
    return m.group(1) if m else None


def _version_tuple(v: str) -> tuple[int, ...]:
    """Lightweight semver-ish compare. We don't need full semver semantics
    (pre-release, build metadata); three integer components is enough."""
    parts = re.findall(r"\d+", v)[:3]
    parts.extend(["0"] * (3 - len(parts)))
    return tuple(int(p) for p in parts)


class Update:
    def __init__(self, ui) -> None:
        self.ui = ui
        self.current_version = __version__.version
        self.latest_version: str | None = None
        self.download_url: str | None = None
        self.download_percent = 0.0

    # ------------------------------------------------------------------
    # Detection
    # ------------------------------------------------------------------
    def check(self) -> bool:
        """Populate latest_version + download_url. Returns True if a newer
        version is available."""
        raw_version = _http_get(PHAROS_VERSION_RAW)
        if raw_version is None:
            return False
        self.latest_version = _parse_version(raw_version.decode("utf-8", errors="replace"))
        if not self.latest_version:
            return False

        raw_ports = _http_get(PHAROS_PORTS_JSON_RAW)
        if raw_ports is not None:
            try:
                data = json.loads(raw_ports.decode("utf-8"))
                for entry in data:
                    if entry.get("name") == PHAROS_PORT_NAME:
                        self.download_url = entry.get("source", {}).get("download_url")
                        break
            except json.JSONDecodeError as e:
                print(f"[Update] ports.json parse failed: {e}")

        return _version_tuple(self.current_version) < _version_tuple(self.latest_version)

    # ------------------------------------------------------------------
    # Download
    # ------------------------------------------------------------------
    def download(self) -> bool:
        """Stream the new zip into PENDING_ZIP with progress UI. Returns success."""
        if not self.download_url:
            print("[Update] No download URL; cannot download.")
            return False

        # If a previous pending zip is still around (e.g. user cancelled
        # mid-extract), drop it so we don't end up applying a stale build.
        if os.path.exists(PENDING_ZIP):
            try:
                os.remove(PENDING_ZIP)
            except OSError:
                pass

        try:
            req = Request(self.download_url, headers={"User-Agent": "Pharos/Updater"})
            with urlopen(req) as resp:
                total = int(resp.getheader("Content-Length", 0)) or 1
                downloaded = 0
                chunk_size = 8192

                with open(PENDING_ZIP, "wb") as out:
                    while True:
                        chunk = resp.read(chunk_size)
                        if not chunk:
                            break
                        out.write(chunk)
                        downloaded += len(chunk)
                        self.download_percent = min(100.0, downloaded / total * 100.0)

                        self.ui.draw_loader(self.download_percent)
                        self.ui.draw_log(
                            text=f"Downloading Pharos v{self.latest_version}... {self.download_percent:.1f}%",
                            background=True,
                        )
                        self.ui.render_to_screen()
                        sdl2.SDL_Delay(16)

            return True
        except (HTTPError, URLError, OSError) as e:
            # OSError covers disk-full / permission failures mid-write — without
            # it, a failed write would propagate up and crash the input handler.
            print(f"[Update] Download failed: {e}")
            if os.path.exists(PENDING_ZIP):
                try:
                    os.remove(PENDING_ZIP)
                except OSError:
                    pass
            return False
