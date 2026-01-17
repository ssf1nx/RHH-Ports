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

GAMEDIR="/${directory}/ports/droidtoolbox"
LOG_DIR="${GAMEDIR}/logs"

mkdir -p "${LOG_DIR}"

cd "${GAMEDIR}" || exit 1

export LOG_FILE="${LOG_DIR}/$(date +'%Y-%m-%d').log"
export LD_LIBRARY_PATH="${GAMEDIR}/libs:${LD_LIBRARY_PATH}"
export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig}"

# Run the app
pm_platform_helper "DroidToolbox" >/dev/null
./SWGE_DroidToolbox > "${LOG_FILE}" 2>&1 || true

# Cleanup
pm_finish
