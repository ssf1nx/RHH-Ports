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

# Set variables
GAMEDIR="/$directory/ports/zelda-mercurischest"
runtime="solarus-2.0.2"

# CD and set logging
cd $GAMEDIR
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Exports
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"

swapabxy() {
    # Only use sdl_controllerconfig if SDL_GAMECONTROLLERCONFIG is empty
    export SDL_GAMECONTROLLERCONFIG="${SDL_GAMECONTROLLERCONFIG:-$sdl_controllerconfig}"

    if [ -z "$SDL_GAMECONTROLLERCONFIG" ]; then
        echo "[swapabxy]: SDL_GAMECONTROLLERCONFIG is empty, cannot swap"
        return
    fi

    if [ ! -x "$GAMEDIR/swapabxy.py" ]; then
        echo "[swapabxy]: $GAMEDIR/tools/swapabxy.py not executable"
        return
    fi

    # Perform the swap
    export SDL_GAMECONTROLLERCONFIG="$(echo "$SDL_GAMECONTROLLERCONFIG" | "$GAMEDIR/swapabxy.py")"
    echo "[swapabxy]: SDL_GAMECONTROLLERCONFIG after swap: $SDL_GAMECONTROLLERCONFIG"
}

# Swap buttons only if swapabxy.txt exists
if [ -f "$GAMEDIR/swapabxy.txt" ]; then
    swapabxy
fi

# Run the game
$GPTOKEYB "$runtime" -c "zmc.gptk" & 
pm_platform_helper "$runtime" > /dev/null
./"$runtime" "$GAMEDIR/"*.solarus

# Cleanup
pm_finish