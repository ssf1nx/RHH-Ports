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

# Variables
GAMEDIR="/${directory}/ports/pharos"
LOG_DIR="${GAMEDIR}/logs"

cd "${GAMEDIR}" || exit 1

# Exports
export XDG_DATA_HOME="${GAMEDIR}"
export LOG_FILE="${LOG_DIR}/$(date +'%Y-%m-%d').log"
export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig}"
export controlfolder
export DEVICE_ARCH

# Permissions etc
chmod +x "${GAMEDIR}/Pharos"
mkdir -p "${LOG_DIR}"

pm_platform_helper "${GAMEDIR}/Pharos" >/dev/null
"${GAMEDIR}/Pharos" "${GAMEDIR}/.sources" > "${LOG_FILE}" 2>&1 || true

pm_finish
