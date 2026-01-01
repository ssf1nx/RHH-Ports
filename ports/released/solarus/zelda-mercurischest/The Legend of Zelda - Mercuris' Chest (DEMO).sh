#!/bin/bash

# Source SDL controls
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi
source $controlfolder/control.txt
get_controls

# Set variables
GAMEDIR="/$directory/ports/zelda-mercurischest"
runtime="solarus-2.0.2"

# CD and set logging
cd $GAMEDIR
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Exports
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"

# Setup Solarus
$ESUDO mkdir -p "$solarus_dir"
$ESUDO umount "$solarus_file" || true
$ESUDO mount "$solarus_file" "$solarus_dir"
PATH="$solarus_dir:$PATH"

# Run the game
$GPTOKEYB "$runtime" -c "zmc.gptk" & 
"$runtime" $GAMEDIR/*.solarus

# Cleanup
pm_finish