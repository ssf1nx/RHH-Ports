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
get_controls
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

# Set variables
GAMEDIR="/$directory/ports/sonic.1"

# CD and set permissions
cd $GAMEDIR
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
$ESUDO chmod +x "$GAMEDIR/RSDKv4"

# Exports
export LD_LIBRARY_PATH="/usr/lib:$GAMEDIR/libs":$LD_LIBRARY_PATH
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

get_res() {
    # RSDK default resolution
    BASE_WIDTH=424
    BASE_HEIGHT=240

    # Calculate integer scale factor for height
    SCALE=$(( DISPLAY_HEIGHT / BASE_HEIGHT ))

    # Calculate scaled width
    SCALED_WIDTH=$(( BASE_WIDTH * SCALE ))

    # If scaled width is too big for screen, reduce until it fits
    while [ $SCALED_WIDTH -gt $DISPLAY_WIDTH ]; do
        BASE_WIDTH=$(( BASE_WIDTH - 1 ))
        SCALED_WIDTH=$(( BASE_WIDTH * SCALE ))
    done

    # Final internal width is base width after adjustment
    WIDTH=$BASE_WIDTH

    # Update settings.ini
    if grep -q "^ScreenWidth=[0-9]\+" "$GAMEDIR/settings.ini"; then
        sed -i "s/^ScreenWidth=[0-9]\+/ScreenWidth=$WIDTH/" "$GAMEDIR/settings.ini"
    else
        echo "Possible invalid or missing settings.ini!"
    fi
}

# Adjust game resolution
get_res

# Run the patcher if the user has dropped any new game/audio files, or on
# first launch after a fresh install.
if [ ! -f "$GAMEDIR/patchlog.txt" ] \
   || [ -f "$GAMEDIR/Sonic1u.rsdk" ] \
   || [ -f "$GAMEDIR/STH1_music.awb" ] \
   || [ -f "$GAMEDIR/STH1_sfx.acb" ] \
   || [ -f "$GAMEDIR/HITE_sfx.acb" ]; then
    if [ -f "$controlfolder/utils/patcher.txt" ]; then
        export PATCHER_FILE="$GAMEDIR/tools/patchscript"
        export PATCHER_GAME="$(basename "${0%.*}")"
        export PATCHER_TIME="a few seconds"
        export controlfolder
        export ESUDO
        export DEVICE_ARCH
        source "$controlfolder/utils/patcher.txt"
        $ESUDO kill -9 $(pidof gptokeyb) 2>/dev/null
    else
        echo "This port requires the latest version of PortMaster."
    fi
fi

# Run the game
$GPTOKEYB "RSDKv4" -c "sonic.gptk" &
pm_platform_helper "RSDKv4" > /dev/null
"$GAMEDIR/RSDKv4"

# Cleanup
pm_finish
