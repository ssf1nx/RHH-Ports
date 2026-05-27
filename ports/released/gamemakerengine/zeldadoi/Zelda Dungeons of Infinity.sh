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
GAMEDIR="/$directory/ports/zeldadoi"

# CD and set permissions
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Mount gmloadernext runtime
GMLOADER="$HOME/gmloadernext"
GMLOADER_RUNTIME="$controlfolder/libs/gmloadernext.squashfs"
if [ -f "$GMLOADER_RUNTIME" ]; then
    $ESUDO mkdir -p "$GMLOADER"
    $ESUDO umount "$GMLOADER" 2>/dev/null || true
    $ESUDO mount "$GMLOADER_RUNTIME" "$GMLOADER"
else
    pm_message "This port requires the gmloadernext runtime. Please download it."
    pm_finish
    exit 1
fi

# Exports
export GMLOADER_LIB_PATH="$GMLOADER/lib"
export LD_LIBRARY_PATH="$GMLOADER/lib:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Unzip data directory if needed
if [ -f "$GAMEDIR/saves/data.zip" ]; then
    cd saves
    if unzip "$GAMEDIR/saves/data.zip"; then
        rm -rf data.zip
        cd ..
    else
        echo "Couldn't unzip saves/data.zip. Please unzip manually."
        exit 1
    fi
fi

function thermal_safety() {
    # Every cpufreq policy (handles big.LITTLE), cap to 80% of current max.
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -w "$policy/scaling_max_freq" ] || continue
        orig=$(cat "$policy/scaling_max_freq") || continue
        target=$((orig * 8 / 10))
        echo "$target" | $ESUDO tee "$policy/scaling_max_freq" > /dev/null
        echo "[thermal] capped $(basename $policy) max: $orig -> $target"
    done
    # Every devfreq node whose name looks like a GPU.
    for devfreq in /sys/class/devfreq/*; do
        [ -w "$devfreq/max_freq" ] || continue
        case "$(basename "$devfreq")" in *gpu*|*GPU*) ;; *) continue ;; esac
        orig=$(cat "$devfreq/max_freq") || continue
        target=$((orig * 8 / 10))
        echo "$target" | $ESUDO tee "$devfreq/max_freq" > /dev/null
        echo "[thermal] capped $(basename "$devfreq") max: $orig -> $target"
    done
    $ESUDO rfkill block wlan bluetooth 2>/dev/null && echo "[thermal] rfkill blocked wlan + bluetooth"
}

case "$DEVICE_CPU" in
    RK3326|h700|a133plus|RK3399|RK3566)
        thermal_safety
        ;;
esac

if [ "${DEVICE_RAM:-0}" -lt 2 ]; then
    pm_message "Dungeons of Infinity is not designed to run well on devices less than 2GB. You will likely experience crashes."
fi

# Assign configs and load the game
$GPTOKEYB "gmloadernext.aarch64" -c "zelda.gptk" &
pm_platform_helper "$GMLOADER/gmloadernext.aarch64" > /dev/null
"$GMLOADER/gmloadernext.aarch64" -c gmloader.json

# Cleanup
$ESUDO umount "$GMLOADER" 2>/dev/null || true
pm_finish
