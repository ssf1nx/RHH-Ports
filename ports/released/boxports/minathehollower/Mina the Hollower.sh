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

source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Variables
GAMEDIR="/$directory/ports/minathehollower"
GAME="$GAMEDIR/data/MinaTheHollower"
BOX64="$GAMEDIR/box64/box64"

# CD and set log
cd "$GAMEDIR/data"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Permissions
chmod +x "$BOX64"

if command -v vulkaninfo >/dev/null 2>&1; then
    if ! vulkaninfo --summary 2>/dev/null | grep -qE "deviceType[[:space:]]*=[[:space:]]*PHYSICAL_DEVICE_TYPE_(INTEGRATED|DISCRETE|VIRTUAL)_GPU"; then
        pm_message "No usable Vulkan GPU detected. Mina the Hollower is Vulkan-only and will not run on this device. See the README."
        pm_finish
        exit 1
    fi
fi

looks_like_installer() {
    head -c 16384 "$1" 2>/dev/null | grep -qE 'filesizes="[0-9]+"'
}

# First run: if the game isn't unpacked yet, look for a dropped-in installer.
if [ ! -f "$GAME" ]; then
    installer=""
    for cand in "$GAMEDIR/data"/*.sh; do
        [ -f "$cand" ] || continue
        if looks_like_installer "$cand"; then installer="$cand"; break; fi
    done
    if [ -z "$installer" ]; then
        if ls "$GAMEDIR/data"/*.sh >/dev/null 2>&1; then
            pm_message "The .sh in the data folder is not a GOG/Humble Linux installer. Copy the correct Linux offline installer, or the already-extracted game files. See the README."
        else
            pm_message "Game data missing. Copy the GOG or Humble Linux offline installer (.sh) into the data folder, or the already-extracted game files. See the README."
        fi
        pm_finish
        exit 1
    fi
    if [ -f "$controlfolder/utils/patcher.txt" ]; then
        export PATCHER_FILE="$GAMEDIR/tools/patchscript"
        export PATCHER_GAME="$(basename "${0%.*}")"
        export PATCHER_TIME="2 to 5 minutes"
        export controlfolder ESUDO DEVICE_ARCH GAMEDIR
        source "$controlfolder/utils/patcher.txt"
        $ESUDO kill -9 $(pidof gptokeyb) 2>/dev/null
    else
        pm_message "This port requires the latest PortMaster. Please visit https://portmaster.games/."
        pm_finish
        exit 1
    fi
    if [ ! -f "$GAME" ]; then
        pm_show_error "Extraction failed. See data/patcherr.txt."
        pm_finish
        exit 1
    fi
fi

chmod +x "$GAME" 2>/dev/null

# Display loading splash
[ "$CFW_NAME" == "muOS" ] && $ESUDO "$GAMEDIR/tools/splash" "$GAMEDIR/splash.png" 1
$ESUDO "$GAMEDIR/tools/splash" "$GAMEDIR/splash.png" 30000 &

# Exports
export LD_LIBRARY_PATH="$GAMEDIR/box64/x64:$GAMEDIR/libs.aarch64:$GAMEDIR/data:$LD_LIBRARY_PATH"
export BOX64_LD_LIBRARY_PATH="$GAMEDIR/box64/x64:$GAMEDIR/data:$LD_LIBRARY_PATH"
export XDG_CONFIG_HOME="$GAMEDIR/config" && mkdir -p "$GAMEDIR/config"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export XDG_DATA_HOME="$GAMEDIR"
export SDL_VIDEODRIVER=x11

# Box64 settings
export BOX64_NOBANNER=1
export BOX64_DYNAREC=1
export BOX64_DYNAREC_SAFEFLAGS=0
export BOX64_DYNAREC_FASTROUND=1
export BOX64_DYNAREC_BIGBLOCK=1
export BOX64_DYNAREC_CALLRET=1
export BOX64_DYNAREC_DIRTY=1
export BOX64_DYNAREC_FORWARD=128
export BOX64_RDTSC_1GHZ=1
export BOX64_VSYNC=0

# Run it
cd "$GAMEDIR/data"
$GPTOKEYB "$(basename "$GAME")" xbox360 &
pm_platform_helper "$GAME" > /dev/null
"$BOX64" "$GAME"

pm_finish
