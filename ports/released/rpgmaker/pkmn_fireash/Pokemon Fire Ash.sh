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
GAMEDIR="/$directory/ports/pkmn_fireash"

# CD and set logging
cd "$GAMEDIR" || exit 1
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Setup permissions
$ESUDO chmod +x "$GAMEDIR/mkxp-z.aarch64"

# Make directories
mkdir -p "$GAMEDIR/config"

# Exports
export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export XDG_DATA_HOME="$GAMEDIR/config"
export LC_ALL=C
export LANG=C

# Unzip stdlib
if [ -f "$GAMEDIR/stdlib.zip" ]; then
    if unzip -q -o "$GAMEDIR/stdlib.zip" -d "$GAMEDIR"; then 
        rm -f "$GAMEDIR/stdlib.zip"
    fi
fi

unzip_data() {
    pm_message "Unzipping game data. This could take a while..."
    local zipfile tmpdir found
    found=0

    # Find the first ZIP
    zipfile=$(find "$GAMEDIR" -maxdepth 1 -type f -name "*.zip" | head -n1)
    [ -n "$zipfile" ] || return 0

    tmpdir=$(mktemp -d) || return 1

    # -o: overwrite files during extraction to tmp
    unzip -q -o "$zipfile" -d "$tmpdir" || { rm -rf "$tmpdir"; return 1; }

    # Find the folder containing Game.ini
    gdir=$(find "$tmpdir" -type d \( -name Game -o -name game \) -print -quit)

    if [ -d "$gdir" ] && [ -f "$gdir/Game.ini" ]; then
        echo "Moving files to $GAMEDIR..."
        # -r: recursive, -f: force, -p: preserve permissions
        # This effectively overwrites existing files within those directories
        cp -rfp "$gdir"/* "$GAMEDIR/"
        found=1
    fi

    rm -rf "$tmpdir"

    if [ "$found" -eq 1 ]; then
        rm -f "$zipfile"
        return 0
    else
        echo "Error: Game.ini not found inside the zip structure."
        return 1
    fi
}

# Run only if a zip exists
if ls "$GAMEDIR"/*.zip 1> /dev/null 2>&1; then
    unzip_data || exit 1
    # Remove files we don't need
    rm -rf "$GAMEDIR/Game.exe"
    rm -rf "$GAMEDIR/Changelog.txt"
    rmdir "$GAMEDIR/Helpful Notes"
fi

# Gptk and run port
$GPTOKEYB "mkxp-z.aarch64" -c "./fireash.gptk" &
pm_platform_helper "$GAMEDIR/mkxp-z.aarch64" >/dev/null
./mkxp-z.aarch64

# Cleanup
pm_finish