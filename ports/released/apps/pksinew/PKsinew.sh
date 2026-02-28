#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-${HOME}/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
	controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
	controlfolder="/opt/tools/PortMaster"
elif [ -d "${XDG_DATA_HOME}/PortMaster/" ]; then
	controlfolder="${XDG_DATA_HOME}/PortMaster"
else
	controlfolder="/roms/ports/PortMaster"
fi

source "${controlfolder}/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/${directory}/ports/pksinew"

cd "${GAMEDIR}" || exit 1

chmod +xwr "$GAMEDIR/PKsinew"

export LD_LIBRARY_PATH="${GAMEDIR}/libs:${LD_LIBRARY_PATH}"
export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig}"
export SDL_VIDEODRIVER="x11"

# Run the app
pm_platform_helper "PKsinew" >/dev/null
./PKsinew

# Cleanup
pm_finish
