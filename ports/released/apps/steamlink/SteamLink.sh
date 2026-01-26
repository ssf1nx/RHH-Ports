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
GAMEDIR="/$directory/ports/steamlink"

# Set config
if [ ! -f "$GAMEDIR/config/SteamLink.conf" ]; then
    bind_directories ~/".config/Valve Corporation" "$GAMEDIR/config"
fi

# Patcher GUI exports
export PATCHER_FILE="$GAMEDIR/config/download"
export PATCHER_GAME="$(basename "${0%.*}")" # This gets the current script filename without the extension
export PATCHER_TIME="a few minutes"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$GAMEDIR/libs.${DEVICE_ARCH}"

# CD and set log
cd $GAMEDIR
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Permissions
chmod +x "$GAMEDIR/config/download"
chmod +x "$GAMEDIR/bin/bsdtar"

run_patcher() {
    if [ -f "$controlfolder/utils/patcher.txt" ]; then
        source "$controlfolder/utils/patcher.txt"
        $ESUDO kill -9 $(pidof gptokeyb)
    else
        echo "This port requires the latest version of PortMaster."
    fi
}

# Check if we need to download Steamlink
if [ "$DEVICE_ARCH" == "aarch64" ]; then
    LIBARCH="/usr/lib/"
    CDN_URL="https://media.steampowered.com/steamlink/rpi/bookworm/arm64/public_build.txt"
    CDN_TXT=$(curl -s "$CDN_URL")
    PACKAGE_URL=$(echo "$CDN_TXT" | grep -o 'https://[^[:space:]]*')
    PACKAGE_VERSION=$(echo "$PACKAGE_URL" | grep 'steamlink-rpi-bookworm-arm64-[0-9]\+\.[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?' | sed -n 's/.*steamlink-rpi-bookworm-arm64-\([0-9.]*\).*/\1/p')
else
    echo "Architecture mismatch: $DEVICE_ARCH!"
fi

# If fetching build info fails, check if we have an existing shell binary
if [[ -z "$CDN_TXT" ]]; then
    if [[ -f "$GAMEDIR/bin/shell" ]]; then
        pm_message "No internet connection. Skipping update check."
    else
        pm_message "SteamLink requires an internet connection to download and use!"
        exit 1
    fi
# If we have an internet connection check the current version
elif [[ -f "$GAMEDIR/bin/version_${DEVICE_ARCH}.txt" ]]; then
    CURRENT_VERSION=$(grep 'steamlink-rpi-bookworm-arm64-[0-9]\+\.[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?' "$GAMEDIR/bin/version_${DEVICE_ARCH}.txt" | sed -n 's/.*steamlink-rpi-bookworm-arm64-\([0-9.]*\).*/\1/p')
    if [[ "$CURRENT_VERSION" != "$PACKAGE_VERSION" ]]; then
        run_patcher
    fi
else
    run_patcher
fi

# Exports post-setup
QT_VERSION=$(ls -d $GAMEDIR/Qt-* 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
game_libs="$LD_LIBRARY_PATH:$GAMEDIR/Qt-${QT_VERSION}/lib"
game_preload="$GAMEDIR/libs.${DEVICE_ARCH}/libhandecoder.so"
game_executable="./"bin/shell.${DEVICE_ARCH}""
export QT_QPA_PLATFORM=eglfs
unset SDL_VIDEO_DRIVER
unset SDL_VIDEO_FORCE_EGL

# Check for dual screens
handle_sway_outputs() {
    if [ -z "$SWAYSOCK" ]; then
        IS_SWAY=0
        return
    fi

    IS_SWAY=1

    # Pick primary: internal panel preferred
    PRIMARY_OUTPUT=$(
        swaymsg -t get_outputs -r 2>/dev/null | jq -r '
            .[]
            | select(.active == true)
            | select(.name | test("^(eDP|DSI|LVDS)"))
            | .name
        ' | head -n1
    )

    # Fallback to first active output
    if [ -z "$PRIMARY_OUTPUT" ]; then
        PRIMARY_OUTPUT=$(
            swaymsg -t get_outputs -r 2>/dev/null | jq -r '
                .[]
                | select(.active == true)
                | .name
            ' | head -n1
        )
    fi

    # Abort safely if nothing active
    if [ -z "$PRIMARY_OUTPUT" ]; then
        IS_SWAY=0
        return
    fi

    # Collect ALL secondary active outputs
    SECONDARY_OUTPUTS=$(
        swaymsg -t get_outputs -r 2>/dev/null | jq -r '
            .[]
            | select(.active == true)
            | select(.name != "'"$PRIMARY_OUTPUT"'")
            | .name
        '
    )

    # Nothing to disable → done
    [ -z "$SECONDARY_OUTPUTS" ] && return

    # Persist list for restore
    printf '%s\n' $SECONDARY_OUTPUTS > /tmp/steamlink_disabled_outputs

    # Disable every secondary output
    while read -r out; do
        swaymsg output "$out" disable >/dev/null
    done <<< "$SECONDARY_OUTPUTS"
}

restore_sway_outputs() {
    [ "$IS_SWAY" -ne 1 ] && return
    [ ! -f /tmp/steamlink_disabled_outputs ] && return

    while read -r out; do
        swaymsg output "$out" enable >/dev/null
    done < /tmp/steamlink_disabled_outputs

    rm -f /tmp/steamlink_disabled_outputs
}

# Get display resolution for libhandecoder
handle_sway_outputs
trap restore_sway_outputs EXIT

if [ "$IS_SWAY" -eq 1 ]; then
    RES=$(swaymsg -t get_outputs | \
        awk -v out="$PRIMARY_OUTPUT" '
        $0 ~ "\"name\": \""out"\"" {f=1}
        f && /"current_mode"/ {getline; getline; print; exit}
        ')
    WIDTH=$(echo "$RES" | grep -o '"width":[0-9]*' | grep -o '[0-9]*')
    HEIGHT=$(echo "$RES" | grep -o '"height":[0-9]*' | grep -o '[0-9]*')
    export HDCD_RESOLUTION="${WIDTH}x${HEIGHT}"
else
    export HDCD_RESOLUTION="${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}"
fi

# Start the game
pm_platform_helper "$GAMEDIR/bin/shell.${DEVICE_ARCH} " >/dev/null
$ESUDO env \
LD_LIBRARY_PATH="$game_libs" \
LD_PRELOAD="$game_preload" \
"$GAMEDIR/bin/shell.${DEVICE_ARCH}"

# Cleanup
restore_sway_outputs
pm_finish