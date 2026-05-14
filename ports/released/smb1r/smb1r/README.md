## Installation
You must provide a copy of Super Mario Bros. for the NES. The launchscript will search for the rom in the port folder and in your `roms/nes` folder. If for some reason it can't use a rom in `roms/nes` (ex. MuOS users) then you can drop a rom in `ports/smb1r`.

The launchscript is designed to check for updates to `SMB1R.arm64` and `SMB1R.pck` if there is an active internet connection.

## Usage
Controls and modernization options can be set in the settings menu. Pressing `Guide` or `M` will take a screenshot and store it in `config/screenshots`. Pressing `L2` will toggle the FPS text in the bottom right. You can rebind these two buttons by modifying `tools/mario.gptk`.

Mods can be found at [Gamebanana](https://gamebanana.com/mods/games/22798) and can be installed in the config folders at `smb1r/config/`.

Custom levels are hosted with nonprofit [Level Share Square](https://levelsharesquare.com/SMBR/levels) and can be installed the same way or can be downloaded directly within SMB1R with an internet connection.

## Building
Super Mario Bros. Remastered is built with [Godot 4.5-beta3](https://godotengine.org/article/dev-snapshot-godot-4-5-beta-3) from a [custom fork](https://github.com/JeodC/Super-Mario-Bros.-Remastered-Public/tree/retro-handheld) tailored to retro handhelds.

## Runtimes

This port requires the following runtimes in `PortMaster/libs`:

- **Westonpack** — [weston_pkg_0.2.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/weston_pkg_0.2.squashfs)

[Pharos](https://github.com/JeodC/RHH-Ports/releases/download/ports-latest/pharos.zip) will fetch these automatically when installing the port. Otherwise download them manually from the [runtimes folder](https://github.com/JeodC/RHH-Ports/tree/main/runtimes) and drop them in `PortMaster/libs`.

## Thanks
JHDev2006 and contributors -- The remaster  
krystalphantasm.bsky.social -- Splash art  
BinaryCounter -- Westonpack which allows the port to run on devices without native x11  