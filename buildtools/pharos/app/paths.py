"""Pharos runtime path constants.

Pharos always runs as a PyInstaller --onefile binary, so:
  - BASE_PATH    is sys._MEIPASS, where bundled resources (fonts/) extract.
  - DATA_DIR     comes from XDG_DATA_HOME, set by the launchscript to the
                 install dir so writable state (manifest, logs, .sources,
                 .pending_update.zip) lands alongside the binary.
  - INSTALL_DIR  is where the binary itself lives on disk; used to derive
                 the extract target for self-update apply.

Running these .py files directly (without PyInstaller) will raise AttributeError
on sys._MEIPASS — that's the intended signal: build with build.sh first.
"""
import os
import sys

BASE_PATH = sys._MEIPASS
DATA_DIR = os.environ["XDG_DATA_HOME"]
INSTALL_DIR = os.path.dirname(os.path.abspath(sys.executable))
