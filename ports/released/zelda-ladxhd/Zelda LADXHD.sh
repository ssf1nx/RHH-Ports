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
GAMEDIR="/$directory/ports/zelda-ladxhd"
GAME="$GAMEDIR/data/LADXHD"

# CD and set logging
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Patch if game binary doesn't exist yet
if [ ! -f "$GAME" ]; then
    if [ -f "$controlfolder/utils/patcher.txt" ]; then
        export PATCHER_FILE="$GAMEDIR/tools/patchscript"
        export PATCHER_GAME="$(basename "${0%.*}")" # This gets the current script filename without the extension
        export PATCHER_TIME="2 to 5 minutes"
        export controlfolder
        export ESUDO
        export DEVICE_ARCH
        source "$controlfolder/utils/patcher.txt"
        $ESUDO kill -9 $(pidof gptokeyb)
    else
        pm_message "This port requires the latest version of PortMaster."
    fi
fi

cd "$GAMEDIR/data"

# Permissions
chmod +x "$GAME"

# Exports
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export LD_LIBRARY_PATH="$GAMEDIR/data:$LD_LIBRARY_PATH"
export XDG_DATA_HOME="$GAMEDIR"

# Run the game
$GPTOKEYB "LADXHD" -c "$GAMEDIR/zelda.gptk" &
pm_platform_helper "$GAME" >/dev/null
"$GAME"

# Cleanup
pm_finish
