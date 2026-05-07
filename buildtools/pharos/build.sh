#!/bin/bash
# Pharos PyInstaller build.
#
# For broad device compatibility (ArkOS-era glibc 2.31 and up), invoke this
# script inside python:3.11-slim-bullseye rather than on the host. The CI
# workflow does this; locally:
#
#   docker run --rm --platform linux/arm64 \
#       -v "$(pwd):/work" -w /work/buildtools/pharos \
#       python:3.11-slim-bullseye bash build.sh
#
# Run on the host directly (not in docker) only if you accept that the
# resulting binary inherits the host's glibc and may fail on older devices.

set -e

PYTHON_MIN=3.11
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/app"
DIST_DIR="$SCRIPT_DIR/dist"
BUILD_DIR="$SCRIPT_DIR/build"

# ---- Python version gate ---------------------------------------------------
PYTHON_BIN=""
for cand in python3.13 python3.12 python3.11 python3; do
    bin=$(command -v "$cand" || true)
    [ -z "$bin" ] && continue
    ver_major=$("$bin" -c 'import sys; print(sys.version_info.major)')
    ver_minor=$("$bin" -c 'import sys; print(sys.version_info.minor)')
    if [ "$ver_major" -ge 3 ] && [ "$ver_minor" -ge 11 ]; then
        PYTHON_BIN="$bin"
        break
    fi
done
if [ -z "$PYTHON_BIN" ]; then
    echo "No Python $PYTHON_MIN+ found." >&2
    echo "On Ubuntu/Debian: sudo apt install python3.11 python3.11-venv" >&2
    echo "If unavailable in apt: add the deadsnakes PPA first:" >&2
    echo "  sudo add-apt-repository ppa:deadsnakes/ppa && sudo apt update" >&2
    exit 1
fi
PYTHON_VER=$($PYTHON_BIN -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "Using Python $PYTHON_VER at $PYTHON_BIN"

# ---- System build deps -----------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
    sudoer=""
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            sudoer="sudo"
        else
            echo "Need apt-get install but not root and sudo missing — skipping." >&2
        fi
    fi
    need_install=()
    command -v objdump >/dev/null 2>&1 || need_install+=(binutils)
    dpkg -s libsdl2-2.0-0 >/dev/null 2>&1 || need_install+=(libsdl2-2.0-0)
    dpkg -s libsdl2-image-2.0-0 >/dev/null 2>&1 || need_install+=(libsdl2-image-2.0-0)
    dpkg -s libsdl2-ttf-2.0-0 >/dev/null 2>&1 || need_install+=(libsdl2-ttf-2.0-0)
    if [ "${#need_install[@]}" -gt 0 ]; then
        echo "Installing system build deps: ${need_install[*]}"
        $sudoer apt-get update -qq
        $sudoer env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${need_install[@]}" >/dev/null
    fi
fi

# ---- Python deps -----------------------------------------------------------
$PYTHON_BIN -m pip install --upgrade pip
$PYTHON_BIN -m pip install --upgrade -r "$SCRIPT_DIR/requirements.txt"

# ---- Build -----------------------------------------------------------------
rm -rf "$DIST_DIR" "$BUILD_DIR"
cd "$SCRIPT_DIR"

pyinstaller \
    --onefile \
    --clean \
    --noconfirm \
    --name Pharos \
    --collect-all sdl2 \
    --add-data "$SOURCE_DIR/fonts:fonts" \
    --paths "$SOURCE_DIR" \
    --distpath "$DIST_DIR" \
    --workpath "$BUILD_DIR" \
    --specpath "$BUILD_DIR" \
    "$SOURCE_DIR/main.py"

echo
echo "Build complete: $DIST_DIR/Pharos"
ls -lh "$DIST_DIR/Pharos"
