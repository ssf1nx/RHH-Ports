#!/bin/bash
# PORTMASTER: soh.zip, Ship of Harkinian.sh

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
GAMEDIR="/$directory/ports/soh"

# Exports
export LD_LIBRARY_PATH="$GAMEDIR/libs":$LD_LIBRARY_PATH
export SDL_GAMECONTROLLERCONFIG=$sdl_controllerconfig
export PATCHER_FILE="$GAMEDIR/assets/otrgen"
export PATCHER_GAME="$(basename "${0%.*}")" # This gets the current script filename without the extension
export PATCHER_TIME="5 to 10 minutes"

# CD and set log
cd $GAMEDIR
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Close the menu if open
sed -i 's/"Menu": *1/"Menu": 0/' shipofharkinian.json

# -------------------- BEGIN FUNCTIONS --------------------

# Check imgui.ini and modify if needed
imgui_reset() {
    input_file="imgui.ini"
    temp_file="imgui_temp.ini"
    skip_section=0
    # Loop through each line in the input file
    while IFS= read -r line; do
        # Check if the line is a window header
        if [[ "$line" =~ ^\[Window\]\[Main\ Game\] || "$line" =~ ^\[Window\]\[Main\ -\ Deck\] ]]; then
            skip_section=1  # Set the flag to skip modifications for this section
        elif [[ "$line" =~ ^\[Window\] ]]; then
            skip_section=0  # Reset the flag for other windows
        fi

        # Modify Pos and Size only if the current section is not skipped
        if [[ $skip_section -eq 0 ]]; then
            if [[ "$line" =~ ^Pos=.* ]]; then
                echo "Pos=30,30" >> "$temp_file"
            elif [[ "$line" =~ ^Size=.* ]]; then
                echo "Size=400,300" >> "$temp_file"
            else
                echo "$line" >> "$temp_file"
            fi
        else
            # If skipping, write the line unchanged
            echo "$line" >> "$temp_file"
        fi
    done < "$input_file"

    # Replace the original file with the modified one
    mv "$temp_file" "$input_file"
}

otr_check() {
    # Extract zip file
    if [ -f assets/extractor.zip ]; then
        echo "Extracting xml files..."
        cd assets
        if unzip -q extractor.zip; then
            rm extractor.zip
            cd ..
        fi
    fi
    
    BASEROMS_DIR="baseroms"

    if [ ! -d "$BASEROMS_DIR" ]; then
        echo "Warning: baseroms directory not found at $BASEROMS_DIR"
        return
    fi

    i=1
    TIME=0
    for romfile in "$BASEROMS_DIR"/*.*64; do
        # Check if glob matched any file
        [ -e "$romfile" ] || { echo "Warning: No ROM files found in $BASEROMS_DIR"; return; }

        # Get file extension
        ext="${romfile##*.}"

        # Rename the file to rom1, rom2, etc.
        newname="$BASEROMS_DIR/rom$i.$ext"
        mv "$romfile" "$newname"
        echo "Renamed $romfile -> $newname"

        # Append to ARGS (no quotes needed)
        ARGS="$ARGS $newname"

        # Add 12000 per ROM to TIME
        TIME=$((TIME + 18000))

        i=$((i + 1))
    done

    # Display loading splash
    [ "$CFW_NAME" == "muOS" ] && $ESUDO "$GAMEDIR/splash" "$GAMEDIR/splash.png" 1
    $ESUDO "$GAMEDIR/splash" "$GAMEDIR/splash.png" $TIME & 
}

# --------------------- END FUNCTIONS ---------------------

# Perform functions
if [ ! -f "oot.o2r" ] || [ ! -f "oot-mq.o2r" ]; then
    otr_check
fi

if [ -f "imgui.ini" ]; then
    imgui_reset
fi

# Run the game
$GPTOKEYB "soh.elf" -c "soh.gptk" & 
pm_platform_helper "soh.elf" >/dev/null
if [ -n "$ARGS" ]; then
    ./soh.elf $ARGS
else
    ./soh.elf
fi

# Rerun script if ARGS is not empty
if [ -n "$ARGS" ]; then
    echo "ARGS not empty, rerunning script..."
    # Clear ARGS to avoid infinite loop
    ARGS=""
    exec "$0" "$@"  # rerun the same script with same arguments
fi

# Cleanup
rm -rf "$GAMEDIR/logs/"
pm_finish
