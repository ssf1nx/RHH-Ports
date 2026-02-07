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
GAMEDIR="/$directory/ports/pkmn_tectonic"

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
    local zipfile tmpdir ini_path gdir
    
    zipfile=$(find "$GAMEDIR" -maxdepth 1 -type f -name "*.zip" | head -n1)
    [ -n "$zipfile" ] || return 0

    tmpdir=$(mktemp -d) || return 1
    unzip -q -o "$zipfile" -d "$tmpdir" || { rm -rf "$tmpdir"; return 1; }

    # Search for the .ini file anywhere in the unzipped content, ignoring case
    ini_path=$(find "$tmpdir" -type f -iname "Project Chasm.ini" -print -quit)

    if [ -n "$ini_path" ]; then
        # Get the directory containing that .ini file
        gdir=$(dirname "$ini_path")
        
        echo "Found .ini at $ini_path. Moving files to $GAMEDIR..."
        cp -rfp "$gdir"/* "$GAMEDIR/"
        
        rm -rf "$tmpdir"
        rm -f "$zipfile"
        return 0
    else
        rm -rf "$tmpdir"
        echo "Error: Project Chasm.ini not found inside the zip structure."
        return 1
    fi
}

# Run only if a zip exists
if ls "$GAMEDIR"/*.zip 1> /dev/null 2>&1; then
    unzip_data || exit 1
    # Remove files we don't need
    rm -rf "$GAMEDIR/Debug Game With PBS Compile.bat"
    rm -rf "$GAMEDIR/Debug Game.bat"
    rm -rf "$GAMEDIR/Essentials Docs Wiki.URL"
    rm -rf "$GAMEDIR/extendtext.exe"
    rm -rf "$GAMEDIR/extendtext.txt"
    rm -rf "$GAMEDIR/Game Linux.x86_64"
    rm -rf "$GAMEDIR/Game.exe"
    rm -rf "$GAMEDIR/GitIgnored Files for Project Chasm.zip"
    rm -rf "$GAMEDIR/Tectonic Updater.jar"
    rm -rf "$GAMEDIR/townmapgen.html"
fi

if [ -d "$GAMEDIR/mkxp" ]; then
    rm -rf "$GAMEDIR/mkxp.json"
    mv "$GAMEDIR/mkxp/mkxp.json" "$GAMEDIR/mkxp.json"
    rmdir "$GAMEDIR/mkxp"
fi

# Gptk and run port
$GPTOKEYB "mkxp-z.aarch64" -c "$GAMEDIR/tectonic.gptk" &
pm_platform_helper "$GAMEDIR/mkxp-z.aarch64" >/dev/null
./mkxp-z.aarch64

# Cleanup
pm_finish