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
GAMEDIR="/$directory/ports/theforceengine"

# CD and set logging
cd $GAMEDIR/engine
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Setup permissions
$ESUDO chmod +xwr "$GAMEDIR/tfe"

# Exports
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export SDL_VIDEODRIVER="x11"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export TFE_DATA_HOME="$GAMEDIR/config"

# --- OpenGL 3.3 check ---
if ! command -v glxinfo >/dev/null 2>&1; then
  echo "ERROR: glxinfo not found; cannot verify OpenGL version."
  exit 1
fi

GL_VERSION_RAW=$(glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL core profile version string/ {print $2}')
[ -z "$GL_VERSION_RAW" ] && GL_VERSION_RAW=$(glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL version string/ {print $2}')

GL_MAJOR=$(echo "$GL_VERSION_RAW" | sed -E 's/^([0-9]+)\..*/\1/')
GL_MINOR=$(echo "$GL_VERSION_RAW" | sed -E 's/^[0-9]+\.([0-9]+).*/\1/')

if [ "$GL_MAJOR" -lt 3 ] || { [ "$GL_MAJOR" -eq 3 ] && [ "$GL_MINOR" -lt 3 ]; }; then
  echo "ERROR: OpenGL 3.3 or higher is required."
  exit 1
fi
# --- end OpenGL check ---

# Assign gptokeyb and load the game
$GPTOKEYB "tfe" -c "$GAMEDIR/tfe.gptk" &
pm_platform_helper "$GAMEDIR/tfe" >/dev/null
./tfe --game DARK

# Cleanup
pm_finish
