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
export PYSDL2_DLL_PATH="/usr/lib"
export LD_LIBRARY_PATH="${GAMEDIR}/libs:${LD_LIBRARY_PATH}"
export controlfolder
export DEVICE_ARCH

mkdir -p "${LOG_DIR}"

# Apply any pending self-update
apply_pending_update() {
    local zip="${GAMEDIR}/.pending_update.zip"
    local parent
    parent="$(dirname "${GAMEDIR}")"
    {
        echo "[Update] Applying pending update from ${zip}..."
        if "$controlfolder/7zzs.${DEVICE_ARCH}" x -y "${zip}" -o"${parent}" >/dev/null; then
            rm -f "${zip}"
            echo "[Update] Applied; re-launching."
            export _PHAROS_UPDATE_APPLIED=1
            exec "$0" "$@"
        else
            echo "[Update] Extraction failed; deleting partial zip."
            rm -f "${zip}"
        fi
    } >> "${LOG_FILE}" 2>&1
}

if [ -f "${GAMEDIR}/.pending_update.zip" ] && [ -z "${_PHAROS_UPDATE_APPLIED}" ]; then
    apply_pending_update "$@"
fi

# Permissions
chmod +x "${GAMEDIR}/Pharos"

pm_platform_helper "${GAMEDIR}/Pharos" >/dev/null
"${GAMEDIR}/Pharos" "${GAMEDIR}/.sources" > "${LOG_FILE}" 2>&1 || true

pm_finish
