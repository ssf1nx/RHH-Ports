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
GAMEDIR="/$directory/ports/simpsons_hnr"

# CD and set logging
cd $GAMEDIR/gamedata
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Setup permissions
$ESUDO chmod +xwr "$GAMEDIR/hitandrun"

# Exports
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export LD_PRELOAD="$GAMEDIR/libs/libfakespace.so"

check_data() {
    # Directories and files to check
    required_dirs=("art" "movies" "scripts" "sound")
    required_files=("ambience.rcf" "carsound.rcf" "dialog.rcf" "music00.rcf" "music01.rcf" "music02.rcf" "music03.rcf" "nis.rcf" "scripts.rcf" "soundfx.rcf")

    missing_items=()

    # Check directories
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$GAMEDIR/gamedata/$dir" ]; then
            missing_items+=("$dir (directory)")
        fi
    done

    # Check files
    for file in "${required_files[@]}"; do
        if [ ! -f "$GAMEDIR/gamedata/$file" ]; then
            missing_items+=("$file (file)")
        fi
    done

    # Report and exit if anything is missing
    if [ ${#missing_items[@]} -ne 0 ]; then
        echo "The following required items are missing from $GAMEDIR:"
        for item in "${missing_items[@]}"; do
            echo " - $item"
        done
        exit 1
    fi
}

# Check for game assets
check_data

# Run game
$GPTOKEYB "hitandrun" -c "$GAMEDIR/hitandrun.gptk" &
pm_platform_helper "$GAMEDIR/hitandrun" >/dev/null
"$GAMEDIR/hitandrun"

# Cleanup
pm_finish