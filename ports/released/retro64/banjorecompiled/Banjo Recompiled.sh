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

GAMEDIR="/$directory/ports/banjorecompiled"

cd $GAMEDIR
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Check vulkan version
vulkan_version=$(vulkaninfo 2>/dev/null | grep -m 1 "apiVersion" | awk '{print $3}')

if [ -z "$vulkan_version" ]; then
    echo "Vulkan not found! This port requires Vulkan 1.2."
    exit 1
fi

v_major=$(echo $vulkan_version | cut -d. -f1)
v_minor=$(echo $vulkan_version | cut -d. -f2)

if [ "$v_major" -lt 1 ] || { [ "$v_major" -eq 1 ] && [ "$v_minor" -lt 2 ]; }; then
    echo "Vulkan version $vulkan_version found. Vulkan 1.2+ is required."
    exit 1
fi

# Permissions
chmod +x "$GAMEDIR/BanjoRecompiled"

# Exports
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export XDG_CONFIG_HOME="$GAMEDIR"

# Check rom
if [ ! -f "$GAMEDIR/bk.n64.us.1.0.z64" ]; then
    rom=$(ls *.z64 *.n64 *.v64 2>/dev/null | head -n 1)
    if [ -z "$rom" ]; then
        echo "There is no rom in $GAMEDIR!"
        exit 1
    fi

    md5=$(md5sum "$rom" | awk '{print $1}')
    if [ "$md5" != "b29599651a13f681c9923d69354bf4a3" ]; then
        echo "The provided rom does not match the requirement!"
        echo "Your rom md5: $md5"
        echo "Target rom md5: b29599651a13f681c9923d69354bf4a3"
        exit 1
    else
        mv "$GAMEDIR/$rom" "$GAMEDIR/bk.n64.us.1.0.z64"
    fi
fi

# Run game
$GPTOKEYB "BanjoRecompiled" -c "banjo.gptk" &
pm_platform_helper "$GAMEDIR/BanjoRecompiled" >/dev/null
./BanjoRecompiled

pm_finish