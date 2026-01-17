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

source "$controlfolder/control.txt"
export PORT_32BIT="Y"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/momodora_rutm"
GAME="$GAMEDIR/gamedata/MomodoraRUtM"
BOX86="$GAMEDIR/box86/box86"
game_libs="$GAMEDIR/box86/x86:$weston_dir/lib_armhf:$GAMEDIR/libs.armhf:/usr/lib32:/lib32"

# Variables
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Permissions
chmod +x "$BOX86"

# Exports
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

export LIBGL_FB=0
export LIBGL_X11=1
export LIBGL_GL=21
export LIBGL_ES=2

export LIBGL_SHRINK=0
export LIBGL_UPLOAD_OPTIMIZE=1
export LIBGL_NPOT=2

export BOX86_DYNAREC_SAFEFLAGS=1
export BOX86_DYNAREC_WAIT=1

# Bind config dir
bind_directories ~/.config/MomodoraRUtM "$GAMEDIR/config"

# Prepare game
find "$GAMEDIR/gamedata" -type f \( \
    -name "*.sh" -o -name "*.so" -o -name "*.out" \
\) -exec rm -f {} \;

# Mount Weston runtime
weston_dir=/tmp/weston
$ESUDO mkdir -p "$weston_dir"
weston_runtime="weston_pkg_0.2"

if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
    if [ ! -f "$controlfolder/harbourmaster" ]; then
        pm_message "This port requires the latest PortMaster. Please visit https://portmaster.games/."
        sleep 5
        exit 1
    fi

    # Try quiet install
    if ! $ESUDO "$controlfolder/harbourmaster" --quiet --no-check runtime_check "${weston_runtime}.squashfs"; then
        pm_message "Failed to install runtime. Please update PortMaster or install '${weston_runtime}' manually."
        sleep 5
        exit 1
    fi
fi

if [ "$PM_CAN_MOUNT" != "N" ]; then
    $ESUDO umount "$weston_dir" 2>/dev/null
fi

$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "$weston_dir"

# Run it
cd "$GAMEDIR/gamedata"
$GPTOKEYB "MomodoraRUtM" -c "$GAMEDIR/momodora.gptk" &
pm_platform_helper "$GAME" > /dev/null
$ESUDO env \
    WRAPPED_LIBRARY_PATH="$game_libs" \
    BOX86_LD_LIBRARY_PATH="$game_libs" \
    $weston_dir/westonwrap32.sh headless noop kiosk crusty_glx_gl4es \
    "$BOX86" "$GAME"

# Cleanup
$ESUDO "$weston_dir/westonwrap32.sh" cleanup
if [ "$PM_CAN_MOUNT" != "N" ]; then
    $ESUDO umount "$weston_dir" 2>/dev/null
fi

pm_finish