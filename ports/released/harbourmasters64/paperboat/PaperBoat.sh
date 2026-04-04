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
GAMEDIR="/$directory/ports/paperboat"

# Exports
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG=$sdl_controllerconfig

# Set up logging
cd $GAMEDIR
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Permissions
$ESUDO chmod +x "$GAMEDIR/PaperBoat"

# Check imgui.ini and modify if needed
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

# Close the menu if open
sed -i 's/"Menu": *1/"Menu": 0/' paperboat.cfg.json

# Check if we need to unzip the assets archive
unzip_assets() {
    # Define 7zzs binary
    SEVENZIP="$controlfolder/7zzs.${DEVICE_ARCH}"
    if [ ! -x "$SEVENZIP" ]; then
        echo "7zzs binary not found at $SEVENZIP"
        return 1
    fi

    if [ -f "$GAMEDIR/assets.zip" ]; then
        echo "Extracting assets.zip..."
        if "$SEVENZIP" x -y "$GAMEDIR/assets.zip" -o"$GAMEDIR" >/dev/null; then
            rm -f "$GAMEDIR/assets.zip"
        else
            echo "Unable to extract assets.zip."
            return 1
        fi
    fi
}

if [ -f "$GAMEDIR/assets.zip" ]; then
    unzip_assets
fi

# Run the game
$GPTOKEYB "PaperBoat" -c "paperboat.gptk" & 
pm_platform_helper "$GAMEDIR/PaperBoat" > /dev/null
./PaperBoat

# Cleanup
rm -rf logs
pm_finish
