#!/usr/bin/env python3
"""
Pharos download worker
"""
import os
import json
import queue
import hashlib
import urllib.request
import urllib.parse
import zipfile
import shutil
import time
from dataclasses import asdict
from pathlib import Path
from contextlib import suppress
from typing import Tuple

from config import Port
from autoinstall import AutoInstaller

# ----------------------------------------------------------------------
# Paths
# ----------------------------------------------------------------------
from paths import DATA_DIR
BASE_DIR = Path(DATA_DIR)
AUTOINSTALL_DIR = BASE_DIR / "autoinstall"
MANIFEST_PATH = BASE_DIR / "resources" / "manifest.json"
AUTOINSTALL_DIR.mkdir(parents=True, exist_ok=True)
MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)

# Runtime environment
controlfolder = os.environ.get("controlfolder", "")
LIBS_DIR = Path(controlfolder) / "libs" if controlfolder else None
DEVICE_ARCH = os.environ.get("DEVICE_ARCH", "")

# ----------------------------------------------------------------------
# GitHub request
# ----------------------------------------------------------------------
def _gh_request(url: str, timeout: int = 30) -> Tuple[bytes, dict]:
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"token {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read(), dict(resp.headers)

# ----------------------------------------------------------------------
# Downloader
# ----------------------------------------------------------------------
class Downloader:
    def __init__(self, dl_queue: queue.Queue, progress_q: queue.Queue):
        self.dl_queue = dl_queue
        self.progress_q = progress_q
        self.autoinstall_dir = AUTOINSTALL_DIR
        self.installer = AutoInstaller(self.autoinstall_dir)

    # ------------------------------------------------------------------
    # Main loop – autoinstall runs as soon as the queue is empty
    # ------------------------------------------------------------------
    def run(self) -> None:
        while True:
            item = self.dl_queue.get()
            if item is None:
                break

            port, kind = item
            self._download_runtimes(port)
            self._download_port(port, kind)

            if self.dl_queue.empty():
                self._run_autoinstall()

            self.dl_queue.task_done()

    # ------------------------------------------------------------------
    # Autoinstall phase
    # ------------------------------------------------------------------
    def _run_autoinstall(self) -> None:
        zip_files = sorted(self.autoinstall_dir.glob("*.zip"))
        if not zip_files:
            return

        self.progress_q.put((0, 1, "Installing packages…", "phase"))
        for zip_file in zip_files:
            name = zip_file.name
            self.progress_q.put((0, 1, f"Installing {name}", "install"))
            result = self.installer.install_zip(name)
            status = "[ERROR] Install failed" if result != 0 else "Installed"
            self.progress_q.put((0, 1, f"{status}: {name}", "install"))
        self.progress_q.put((0, 1, "Installation complete", "install"))

    # ------------------------------------------------------------------
    # Image fetcher
    # ------------------------------------------------------------------
    def fetch_repo_images(self, repo: 'Repository') -> None:
        if not repo.images_zip_url or not repo.images_dir:
            return

        images_dir = Path(repo.images_dir)
        images_dir.mkdir(parents=True, exist_ok=True)
        metadata_path = images_dir / "images.json"

        # Load existing metadata
        local_meta = {}
        if metadata_path.exists():
            with suppress(Exception):
                with open(metadata_path, "r", encoding="utf-8") as f:
                    local_meta = json.load(f)

        # Query release
        try:
            parts = urllib.parse.urlparse(repo.images_zip_url).path.split("/")
            owner, repo_name, _, _, tag = parts[1:6]
            api_url = f"https://api.github.com/repos/{owner}/{repo_name}/releases/tags/{tag}"
            data, _ = _gh_request(api_url)
            release = json.loads(data)
        except Exception as e:
            print(f"[ERROR] Query release {repo.name}: {e}")
            return

        asset = next((a for a in release.get("assets", []) if a["name"] == "images.zip"), None)
        if not asset:
            return

        remote_id = asset.get("id")
        remote_size = asset.get("size", 0)
        if local_meta.get("id") == remote_id and local_meta.get("size") == remote_size:
            return

        img_zip = images_dir / "images.zip"
        try:
            data, _ = _gh_request(asset["browser_download_url"], timeout=60)
            with open(img_zip, "wb") as f:
                f.write(data)

            # Clean old files
            for item in images_dir.iterdir():
                if item not in (metadata_path, img_zip):
                    if item.is_dir():
                        shutil.rmtree(item, ignore_errors=True)
                    else:
                        item.unlink(missing_ok=True)

            with zipfile.ZipFile(img_zip, "r") as zf:
                zf.extractall(images_dir)

            with open(metadata_path, "w", encoding="utf-8") as f:
                json.dump({"id": remote_id, "size": remote_size}, f)

            img_zip.unlink()
            print(f"[OK] Updated images for {repo.name}")
        except Exception as e:
            print(f"[ERROR] Image update failed for {repo.name}: {e}")
            with suppress(OSError):
                img_zip.unlink()

    # ------------------------------------------------------------------
    # Runtime downloads
    # ------------------------------------------------------------------
    def _download_runtimes(self, port: Port) -> None:
        if not port.runtime or not port.runtime_base_url:
            return
        if DEVICE_ARCH != "aarch64":
            print(f"[RUNTIME] Skipping (arch={DEVICE_ARCH!r}, need aarch64)")
            return
        if not LIBS_DIR:
            print("[RUNTIME] Skipping (controlfolder not set)")
            return

        LIBS_DIR.mkdir(parents=True, exist_ok=True)
        manifest_runtimes = self._load_runtime_manifest()

        for rt_name in port.runtime:
            rt_path = LIBS_DIR / rt_name

            if rt_path.exists():
                if manifest_runtimes.get(rt_name, {}).get("md5"):
                    print(f"[RUNTIME] {rt_name} present, skipping")
                    continue
                # On disk but not in manifest – record its md5 so we skip next time
                print(f"[RUNTIME] {rt_name} found on disk, recording md5")
                manifest_runtimes[rt_name] = {"md5": self._md5_file(rt_path)}
                self._save_runtime_manifest(manifest_runtimes)
                continue

            url = f"{port.runtime_base_url}/{rt_name}"
            print(f"[RUNTIME] Downloading {rt_name}")
            self.progress_q.put((0, 1, f"Runtime: {rt_name}", "download"))
            tmp_path = rt_path.with_suffix(".tmp")

            try:
                req = urllib.request.Request(url, headers={"User-Agent": "Pharos/1.0"})
                with urllib.request.urlopen(req, timeout=60) as resp:
                    total = int(resp.headers.get("Content-Length", 0))
                    downloaded = 0
                    chunk = 64 * 1024
                    start = time.time()

                    with open(tmp_path, "wb") as f:
                        while True:
                            data = resp.read(chunk)
                            if not data:
                                break
                            f.write(data)
                            downloaded += len(data)
                            elapsed = time.time() - start
                            speed = (downloaded / (1024 * 1024)) / elapsed if elapsed else 0
                            pct = (downloaded / total * 100) if total else 0
                            self.progress_q.put((
                                downloaded, total or downloaded,
                                f"Runtime: {rt_name} ({pct:.1f}%) \u2013 {speed:.2f} MB/s",
                                "download",
                            ))

                os.replace(tmp_path, rt_path)
                md5 = self._md5_file(rt_path)
                manifest_runtimes[rt_name] = {"md5": md5}
                self._save_runtime_manifest(manifest_runtimes)
                self.progress_q.put((1, 1, f"Runtime installed: {rt_name}", "download"))
                print(f"[RUNTIME] Installed {rt_name} (md5={md5[:8]}...)")

            except Exception as e:
                print(f"[RUNTIME ERROR] {rt_name}: {type(e).__name__}: {e}")
                self.progress_q.put((0, 1, f"Runtime failed: {rt_name}", "download"))
                with suppress(OSError):
                    tmp_path.unlink()

    def _load_runtime_manifest(self) -> dict:
        if MANIFEST_PATH.exists():
            with suppress(Exception):
                with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
                    return json.load(f).get("runtimes", {})
        return {}

    def _save_runtime_manifest(self, runtimes: dict) -> None:
        data = {}
        if MANIFEST_PATH.exists():
            with suppress(Exception):
                with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
                    data = json.load(f)
        data["runtimes"] = runtimes
        tmp = MANIFEST_PATH.with_suffix(".tmp")
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, MANIFEST_PATH)
        except Exception as e:
            print(f"[ERROR] Runtime manifest update failed: {e}")
            with suppress(OSError):
                tmp.unlink()

    @staticmethod
    def _md5_file(path: Path) -> str:
        h = hashlib.md5()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(64 * 1024), b""):
                h.update(chunk)
        return h.hexdigest()

    # ------------------------------------------------------------------
    # Single-port download (streaming)
    # ------------------------------------------------------------------
    def _download_port(self, port: Port, kind: str) -> None:
        print(f"[DOWNLOAD] Starting: {port.name} from {port.download_url!r}")
        zip_path = self.autoinstall_dir / f"{port.name}.zip"
        try:
            req = urllib.request.Request(
                port.download_url,
                headers={"User-Agent": "Pharos/1.0"}
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                total = int(resp.headers.get("Content-Length", 0))
                print(f"[DOWNLOAD] Content-Length: {total} bytes")
                downloaded = 0
                chunk = 64 * 1024
                start = time.time()

                with open(zip_path, "wb") as f:
                    while True:
                        data = resp.read(chunk)
                        if not data:
                            break
                        f.write(data)
                        downloaded += len(data)

                        elapsed = time.time() - start
                        speed = (downloaded / (1024*1024)) / elapsed if elapsed else 0
                        pct = (downloaded / total * 100) if total else 100

                        self.progress_q.put((
                            downloaded,
                            total or downloaded,
                            f"{port.title} ({pct:.1f}%) – {speed:.2f} MB/s",
                            "download"
                        ))

            # Final sticky message
            self.progress_q.put((
                downloaded, downloaded,
                f"Downloaded: {port.title}",
                "download"
            ))

            # Manifest update
            with open(zip_path, "rb") as f:
                md5_hash = hashlib.md5(f.read()).hexdigest()
            port.md5 = md5_hash
            port.size = zip_path.stat().st_size
            self._update_manifest(port, kind)
            
            print(f"[DOWNLOAD] Complete: {zip_path} ({downloaded} bytes, {time.time()-start:.1f}s)")

        except Exception as e:
            print(f"[DOWNLOAD ERROR] {port.name}: {type(e).__name__}: {e}")
            self._fail(port, f"{type(e).__name__}: {e}")
            with suppress(OSError):
                zip_path.unlink()

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _fail(self, port: Port, message: str) -> None:
        self.progress_q.put((0, 1, f"Failed {port.name}.zip: {message}", "download"))
        print(f"[ERROR] {message}")

    def _update_manifest(self, port: Port, kind: str) -> None:
        data = {"ports": [], "bottles": []}
        if MANIFEST_PATH.exists():
            with suppress(Exception):
                with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
                    data = json.load(f)

        key = "ports" if kind == "port" else "bottles"
        other_key = "bottles" if kind == "port" else "ports"

        data[key] = [
            d for d in data.get(key, [])
            if d.get("name", "").lower() != port.name.lower()
        ]
        data[key].append(asdict(port))
        data[other_key] = data.get(other_key, [])

        tmp = MANIFEST_PATH.with_suffix(".tmp")
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, MANIFEST_PATH)
        except Exception as e:
            print(f"[ERROR] Manifest update failed: {e}")
            with suppress(OSError):
                tmp.unlink()