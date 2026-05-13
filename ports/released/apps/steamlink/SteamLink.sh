#!/bin/bash
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Variables
GAMEDIR="/$directory/ports/steamlink"

# Set config
if [ ! -f "$GAMEDIR/config/SteamLink.conf" ]; then
    bind_directories ~/".config/Valve Corporation" "$GAMEDIR/config"
fi

# Exports
export PATCHER_FILE="$GAMEDIR/config/download"
export PATCHER_GAME="$(basename "${0%.*}")" # This gets the current script filename without the extension
export PATCHER_TIME="a few minutes"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$GAMEDIR/libs.${DEVICE_ARCH}"
export QT_VERSION=$(ls -d $GAMEDIR/Qt-* 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)

# CD and set log
cd $GAMEDIR
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Permissions
chmod +x -R "$GAMEDIR/config"
chmod +x "$GAMEDIR/bin/bsdtar"

# ---- RK3566 + Batocera Mali ----
# Batocera ships mesa-panfork (Mesa 22.x era) for Mali GPUs, which doesn't
# satisfy Qt 5.14.1 eglfs requirements that Valve's Steam Link build
# expects. RK3566 + Batocera devices need a self-contained AppImage that
# bundles its own Mesa 26 + LLVM 20 stack.
case "$DEVICE_CPU:$CFW_NAME" in
    RK3566:Batocera)
        echo "[STEAMLINK] RK3566 + Batocera detected — using bundled AppImage."

        # AppImage sourced from suckbluefrog
        APPIMAGE_URL="https://github.com/suckbluefrog/batocera.linux/releases/download/stuff/Steamlink-aarch64-rk3566.AppImage"
        APPIMAGE_DST="$GAMEDIR/Steamlink-aarch64-rk3566.AppImage"

        if [ ! -f "$APPIMAGE_DST" ]; then
            pm_message "Downloading Steam Link AppImage for RK3566 (~92 MB)..."
            if ! curl -fL --retry 3 --connect-timeout 15 "$APPIMAGE_URL" -o "$APPIMAGE_DST"; then
                pm_message "AppImage download failed. Check internet connection."
                sleep 5
                pm_finish
                exit 1
            fi
            chmod +x "$APPIMAGE_DST"
        fi

        # Env the bundled Steam Link build expects (mirrors suckbluefrog's wrapper)
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run}"
        export APPIMAGE_EXTRACT_AND_RUN=1
        mkdir -p "${TMPDIR:-/tmp}"

        pm_platform_helper "$APPIMAGE_DST" > /dev/null
        "$APPIMAGE_DST"

        pm_finish
        exit 0
        ;;
esac

run_patcher() {
    if [ -f "$controlfolder/utils/patcher.txt" ]; then
        source "$controlfolder/utils/patcher.txt"
        $ESUDO kill -9 $(pidof gptokeyb)
    else
        echo "This port requires the latest version of PortMaster."
    fi
}

# Check if we need to download Steamlink
if [ "$DEVICE_ARCH" == "aarch64" ]; then
    LIBARCH="/usr/lib/"
    CDN_URL="https://media.steampowered.com/steamlink/rpi/bookworm/arm64/public_build.txt"
    CDN_TXT=$(curl -s "$CDN_URL")
    PACKAGE_URL=$(echo "$CDN_TXT" | grep -o 'https://[^[:space:]]*')
    PACKAGE_VERSION=$(echo "$PACKAGE_URL" | grep 'steamlink-rpi-bookworm-arm64-[0-9]\+\.[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?' | sed -n 's/.*steamlink-rpi-bookworm-arm64-\([0-9.]*\).*/\1/p')
else
    echo "Architecture mismatch: $DEVICE_ARCH!"
fi

# If fetching build info fails, check if we have an existing shell binary
if [[ -z "$CDN_TXT" ]]; then
    if [[ -f "$GAMEDIR/bin/shell" ]]; then
        pm_message "No internet connection. Skipping update check."
    else
        pm_message "SteamLink requires an internet connection to download and use!"
        exit 1
    fi
# If we have an internet connection check the current version
elif [[ -f "$GAMEDIR/bin/version_${DEVICE_ARCH}.txt" ]]; then
    CURRENT_VERSION=$(grep 'steamlink-rpi-bookworm-arm64-[0-9]\+\.[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?' "$GAMEDIR/bin/version_${DEVICE_ARCH}.txt" | sed -n 's/.*steamlink-rpi-bookworm-arm64-\([0-9.]*\).*/\1/p')
    if [[ "$CURRENT_VERSION" != "$PACKAGE_VERSION" ]]; then
        run_patcher
    fi
else
    run_patcher
fi

# --- Display Setup Block ---
# Define default fallbacks (No-op)
setup_display() { export HDCD_RESOLUTION="${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}"; }
cleanup_display() { :; }

# Source the correct helper
if [ -n "$SWAYSOCK" ] && [ -f "$GAMEDIR/config/helper_sway" ]; then
    echo "[STEAMLINK] Sway detected, sourcing helper_sway"
    source "$GAMEDIR/config/helper_sway"
else
    echo "[STEAMLINK] No sway detected, sourcing helper_x11"
    source "$GAMEDIR/config/helper_x11"
fi

# Execute hooks
setup_display
trap cleanup_display EXIT
# ---------------------------

# Start the game
pm_platform_helper "$GAMEDIR/bin/shell.${DEVICE_ARCH} " >/dev/null
launch_app

# Cleanup
cleanup_display
pm_finish