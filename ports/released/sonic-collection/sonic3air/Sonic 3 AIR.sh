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
GAMEDIR="/$directory/ports/sonic3air"

cd $GAMEDIR
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Exports
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Create config dir
mkdir -p "config"
bind_directories "$XDG_DATA_HOME/Sonic3AIR" "$GAMEDIR/config"

# Patch config.json
if [ -f "$GAMEDIR/config.json" ]; then
  sed -i "s|\"StartPhase\":[[:space:]]*\"[0-9]*\"|\"StartPhase\": \"0\"|" "$GAMEDIR/config.json"
  sed -i "s|\"WindowSize\":[[:space:]]*\"[0-9]\+[[:space:]]*x[[:space:]]*[0-9]\+\"|\"WindowSize\": \"${DISPLAY_WIDTH} x ${DISPLAY_HEIGHT}\"|" "$GAMEDIR/config.json"
  sed -i "s|\"EnforceDebugMode\":[[:space:]]*\"[0-9]*\"|\"EnforceDebugMode\": \"1\"|" "$GAMEDIR/config.json"
fi

# # Extract audioremaster.bin
if [ -f "$GAMEDIR/audioremaster.7z.001" ]; then
  SEVENZIP="$controlfolder/7zzs.${DEVICE_ARCH}"
  if [ ! -x "$SEVENZIP" ]; then
    echo "7zzs binary not found at $SEVENZIP; aborting extraction."
    pm_finish; exit 1
  fi
  echo "Extracting audioremaster.bin (split archive)..."
  rm -f "$GAMEDIR/data/audioremaster.bin"
  if "$SEVENZIP" x -y "$GAMEDIR/audioremaster.7z.001" -o"$GAMEDIR/data" >/dev/null; then
    rm -f "$GAMEDIR"/audioremaster.7z.*
  else
    echo "Unable to extract audioremaster.7z."
    pm_finish; exit 1
  fi
fi

# Run the game
$GPTOKEYB "sonic3air_linux" -c "sonic.gptk" &
./sonic3air_linux

# Cleanup
pm_finish
