## Installation
You must provide a copy of Super Mario Bros. for the NES. The launchscript will search for the rom in the port folder and in your `roms/nes` folder. If for some reason it can't use a rom in `roms/nes` (ex. MuOS users) then you can drop a rom in `ports/smb1r`.

The launchscript is designed to check for updates to `SMB1R.pck` if there is an active internet connection.

## Usage
Controls and modernization options can be set in the settings menu. The port relies on GPToKeyB controls.

Mods can be found at [Gamebanana](https://gamebanana.com/mods/games/22798) and can be installed in the config folders at `smb1r/config/`.

Custom levels are hosted with nonprofit [Level Share Square](https://levelsharesquare.com/SMBR/levels) and can be installed the same way or can be downloaded directly within SMB1R with an internet connection.

## Building
Super Mario Bros. Remastered is built with [Godot 4.5-beta3](https://godotengine.org/article/dev-snapshot-godot-4-5-beta-3) from a [custom fork](https://github.com/JeodC/Super-Mario-Bros.-Remastered-Public/tree/retro-handheld) tailored to retro handhelds.

## Thanks
JHDev2006 and contributors -- The remaster  
krystalphantasm.bsky.social -- Splash art  
BinaryCounter -- Westonpack which allows the port to run on devices without native x11  