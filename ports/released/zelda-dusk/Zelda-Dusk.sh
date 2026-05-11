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
GAMEDIR="/$directory/ports/zelda-dusk"
GAME="$GAMEDIR/dusk"

# Vulkan check
check_vulkan() {
    if command -v vulkaninfo >/dev/null 2>&1; then
        vulkaninfo --summary 2>/dev/null | grep -q deviceName && return 0
        return 1
    fi
    # No vulkaninfo: fall back to loader + ICD JSON existence.
    if ! ldconfig -p 2>/dev/null | grep -q libvulkan.so.1 \
        && [ ! -e /usr/lib/aarch64-linux-gnu/libvulkan.so.1 ] \
        && [ ! -e /usr/lib/libvulkan.so.1 ]; then
        return 1
    fi
    for d in /usr/share/vulkan/icd.d /etc/vulkan/icd.d /usr/local/share/vulkan/icd.d; do
        ls "$d"/*.json >/dev/null 2>&1 && return 0
    done
    return 1
}

if ! check_vulkan; then
    pm_message "Dusk requires Vulkan, which is not available on this device. The port cannot run."
    sleep 5
    pm_finish
    exit 1
fi

# CD and set log
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
$ESUDO chmod +x "$GAME"

# Create directories
mkdir -p "$GAMEDIR/config"

# Exports
export XDG_DATA_HOME="$GAMEDIR/config"
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Vulkan / Mesa hints (kept lean; tweak per device if needed)
export MESA_VK_WSI_PRESENT_MODE=mailbox

# Locate the disc image directly in the port folder
DVD=""
for ext in ciso iso gcm rvz nkit.iso; do
    for f in "$GAMEDIR"/*."$ext"; do
        [ -f "$f" ] && DVD="$f" && break 2
    done
done

if [ -z "$DVD" ]; then
    pm_message "No Twilight Princess disc image found in ports/zelda-dusk."
    sleep 5
    pm_finish
    exit 1
fi

# Patch the disc image path into Dusk's config
CONFIG="$GAMEDIR/config/TwilitRealm/Dusk/config.json"
CURRENT=$(sed -n 's/.*"backend\.isoPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG" 2>/dev/null)
if [ -z "$CURRENT" ] || [ ! -f "$CURRENT" ]; then
    DVD_ESC=$(printf '%s' "$DVD" | sed 's/[\\&|]/\\&/g')
    sed -i "s|\"backend\.isoPath\": \"[^\"]*\"|\"backend.isoPath\": \"$DVD_ESC\"|" "$CONFIG"
fi

# Run the game
$GPTOKEYB "dusk" -c "zelda-dusk.gptk" &
pm_platform_helper "$GAME" >/dev/null
"$GAME" --backend vulkan

# Cleanup -- we already have log.txt, purge the rest to prevent bloat
rm -rf "$GAMEDIR/config/TwilitRealm/Dusk/logs/"*
pm_finish
