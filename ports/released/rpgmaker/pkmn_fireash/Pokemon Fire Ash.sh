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
SEVEN_ZIP="$controlfolder/7zzs.${DEVICE_ARCH}"

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
export PCKILLMODE="Y"

# Unzip stdlib
if [ -f "$GAMEDIR/stdlib.zip" ]; then
    if "$SEVEN_ZIP" x -y -bso0 -bsp0 "$GAMEDIR/stdlib.zip" -o"$GAMEDIR"; then
        rm -f "$GAMEDIR/stdlib.zip"
    fi
fi

unzip_data() {
    pm_message "Unzipping game data. This could take a while..."
    local zipfile ini_path gdir entry name

    zipfile=$(find "$GAMEDIR" -maxdepth 1 -type f -name "*.zip" | head -n1)
    [ -n "$zipfile" ] || return 0

    "$SEVEN_ZIP" x -y -bso0 -bsp0 "$zipfile" -o"$GAMEDIR" || return 1

    ini_path=$(find "$GAMEDIR" -mindepth 2 -type f -iname "Game.ini" -print -quit)
    [ -z "$ini_path" ] && \
        ini_path=$(find "$GAMEDIR" -maxdepth 1 -type f -iname "Game.ini" -print -quit)

    if [ -z "$ini_path" ]; then
        echo "Error: Game.ini not found inside the zip structure."
        return 1
    fi

    gdir=$(dirname "$ini_path")
    if [ "$gdir" != "$GAMEDIR" ]; then
        echo "Lifting game files from $gdir to $GAMEDIR..."
        find "$gdir" -mindepth 1 -maxdepth 1 -print0 | \
            while IFS= read -r -d '' entry; do
                name="${entry##*/}"
                if [ -d "$entry" ] && [ -d "$GAMEDIR/$name" ]; then
                    cp -rfp "$entry/." "$GAMEDIR/$name/" && rm -rf "$entry"
                else
                    mv -f "$entry" "$GAMEDIR/$name"
                fi
            done
        rmdir "$gdir" 2>/dev/null || true
    fi

    rm -f "$zipfile"
    return 0
}

# Run only if a zip exists
if ls "$GAMEDIR"/*.zip 1> /dev/null 2>&1; then
    unzip_data || exit 1
    # Remove files we don't need
    rm -rf "$GAMEDIR/Game.exe"
    rm -rf "$GAMEDIR/Changelog.txt"
    rmdir "$GAMEDIR/Helpful Notes"
    # Force onscreen keyboard (patch USEKEYBOARD=false inside Scripts.rxdata)
    PY="${PYTHON:-python3}"
    command -v "$PY" >/dev/null 2>&1 || PY=python
    if command -v "$PY" >/dev/null 2>&1 && [ -f "$GAMEDIR/Data/Scripts.rxdata" ]; then
        "$PY" "$GAMEDIR/patch_textentry.py" "$GAMEDIR/Data/Scripts.rxdata" || \
            pm_message "Warning: keyboard patch failed; name entry may be stuck."
    else
        pm_message "Warning: python not found; keyboard patch skipped."
    fi
fi

# Gptk and run port
$GPTOKEYB "mkxp-z.aarch64" -c "./fireash.gptk" &
pm_platform_helper "$GAMEDIR/mkxp-z.aarch64" >/dev/null
./mkxp-z.aarch64

# Cleanup
pm_finish