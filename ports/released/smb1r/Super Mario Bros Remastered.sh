#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# Detect PortMaster control folder
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
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Paths
GAMEDIR="/$directory/ports/smb1r"
CONFDIR="$GAMEDIR/config"

# CD and set up log and permissions
cd "$GAMEDIR"
exec > "$GAMEDIR/log.txt" 2>&1
$ESUDO chmod +rwx "$GAMEDIR/SMB1R.arm64"
$ESUDO chmod +rwx "$GAMEDIR/tools/splash"
$ESUDO chmod +rwx "$GAMEDIR/tools/crc32.py"

# Exports
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export GODOT_SILENCE_ROOT_WARNING=1

# --- ROM detection & validation (CRC32) ---
find_and_copy_rom() {
	VALID_CRC32S=("3337EC46" "393A432F")
	NES_DIR="/$directory/nes"

	check_crc() {
		local rom_path="$1"
		local crc
		crc=$($GAMEDIR/tools/crc32.py "$rom_path" | awk '{print $1}')
		printf '%s\n' "${VALID_CRC32S[@]}" | grep -q -i "$crc"
	}

	# 1. Check if a valid ROM already exists in $GAMEDIR
	for rom in "$GAMEDIR"/*.nes; do
		[ -e "$rom" ] || continue
		if check_crc "$rom"; then
			echo "Valid ROM already exists in $GAMEDIR. Nothing to do."
			return
		fi
	done

	# 2. Search NES directory for a valid ROM to copy
	for dir in "$NES_DIR"; do
		[ -d "$dir" ] || continue
		echo "Searching in $dir..."

		# 2a. Plain .nes files
		for rom in "$dir"/*.nes; do
			[ -e "$rom" ] || continue
			if check_crc "$rom"; then
				echo "Valid ROM found: $rom"
				cp "$rom" "$GAMEDIR"
				return
			fi
		done

		# 2b. .nes files inside zip archives
		for zip in "$dir"/*.zip; do
			[ -e "$zip" ] || continue
			echo "Checking zip: $zip"
			tmpfile=$(mktemp)
			unzip -Z1 "$zip" | grep -i '\.nes$' > "$tmpfile"
			while read -r nes_file; do
				tmpnes=$(mktemp)
				unzip -p "$zip" "$nes_file" > "$tmpnes" 2>/dev/null
				if check_crc "$tmpnes"; then
					echo "Valid ROM found inside zip: $zip -> $nes_file"
					cp "$tmpnes" "$GAMEDIR"
					rm -f "$tmpnes"
					rm -f "$tmpfile"
					return
				fi
				rm -f "$tmpnes"
			done < "$tmpfile"
			rm -f "$tmpfile"
		done
	done

	echo "No valid ROM found in $NES_DIR!"
	exit 1
}

# --- Check for PCK updates ---
update_check() {
	remote_url="https://raw.githubusercontent.com/JeodC/RHH-Ports/main/ports/released/smb1r/smb1r/SMB1R.pck"
	local_pck="$GAMEDIR/SMB1R.pck"
	etag_file="$GAMEDIR/.SMB1R.pck.etag"
	SPLASH="splash.png"

	echo "Checking for PCK updates..."

	remote_etag=$(curl -sI -L "$remote_url" | grep -i '^etag:' | cut -d'"' -f2)

	if [ -z "$remote_etag" ]; then
		echo "Could not determine remote ETag. Skipping PCK update check."
		[ "$CFW_NAME" = "muOS" ] && $ESUDO "$GAMEDIR/tools/splash" "$GAMEDIR/tools/$SPLASH" 1
		$ESUDO "$GAMEDIR/tools/splash" "$GAMEDIR/tools/$SPLASH" 8000 &
		return
	fi

	download_needed=0

	if [ ! -f "$local_pck" ]; then
		echo "SMB1R.pck is missing. Will download latest."
		SPLASH="update.png"
		download_needed=1
	elif [ ! -f "$etag_file" ] || [ "$remote_etag" != "$(cat "$etag_file")" ]; then
		echo "Newer PCK found. Will update."
		SPLASH="update.png"
		download_needed=1
	else
		echo "SMB1R.pck is up-to-date."
		[ "$CFW_NAME" = "muOS" ] && $ESUDO "$GAMEDIR/tools/splash" "$GAMEDIR/tools/$SPLASH" 1
		$ESUDO "$GAMEDIR/tools/splash" "$GAMEDIR/tools/$SPLASH" 8000 &
	fi

	if [ $download_needed -eq 1 ]; then
		[ "$CFW_NAME" = "muOS" ] && $ESUDO "$GAMEDIR/tools/splash" "$GAMEDIR/tools/$SPLASH" 1
		$ESUDO "$GAMEDIR/tools/splash" "$GAMEDIR/tools/$SPLASH" 16000 &
		echo "Downloading SMB1R.pck..."
		if curl -L -o "$local_pck" "$remote_url"; then
			chmod +r "$local_pck"
			echo "$remote_etag" > "$etag_file"
			echo "Download complete."
		else
			echo "Failed to download SMB1R.pck — please check your internet connection!"
			[ ! -f "$local_pck" ] && exit 1
		fi
	fi
}

# Run update check
update_check

# Run ROM search
if [ ! -f "$GAMEDIR/config/baserom.nes" ]; then
    find_and_copy_rom
fi

# Mount Weston runtime
weston_dir=/tmp/weston
$ESUDO mkdir -p "$weston_dir"
weston_runtime="weston_pkg_0.2"
if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
	if [ ! -f "$controlfolder/harbourmaster" ]; then
		pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
		sleep 5
		exit 1
	fi
	$ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${weston_runtime}.squashfs"
fi

if [ "$PM_CAN_MOUNT" != "N" ]; then
	$ESUDO umount "$weston_dir"
fi

$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "$weston_dir"

# Launch game
$GPTOKEYB "SMB1R.arm64" -c "$GAMEDIR/tools/mario.gptk" &

$ESUDO env $weston_dir/westonwrap.sh headless noop kiosk crusty_x11egl \
	./SMB1R.arm64 \
	--resolution ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} -f \
	--rendering-driver opengl3_es \
	--main-pack SMB1R.pck

# Clean up
$ESUDO $weston_dir/westonwrap.sh cleanup
if [ "$PM_CAN_MOUNT" != "N" ]; then
	$ESUDO umount "$weston_dir"
fi
pm_finish
